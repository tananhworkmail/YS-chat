package services

import (
	"context"
	"errors"
	"strings"
	"time"

	"web-api/internal/pkg/config"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	ErrCallNotFound          = "CALL_NOT_FOUND"
	ErrCallConflict          = "CALL_CONFLICT"
	ErrCallInvalidTransition = "CALL_INVALID_TRANSITION"
)

type CallRecord struct {
	CallID             string     `json:"callId" gorm:"column:call_id;primaryKey"`
	ConversationID     uint64     `json:"conversationId" gorm:"column:conversation_id"`
	CallerUserid       string     `json:"caller" gorm:"column:caller_userid"`
	CalleeUserid       string     `json:"callee" gorm:"column:callee_userid"`
	MediaType          string     `json:"mediaType" gorm:"column:media_type"`
	AcceptedByDeviceID string     `json:"acceptedByDeviceId,omitempty" gorm:"column:accepted_by_device_id"`
	StartedAt          time.Time  `json:"startedAt" gorm:"column:started_at"`
	AnsweredAt         *time.Time `json:"answeredAt,omitempty" gorm:"column:answered_at"`
	EndedAt            *time.Time `json:"endedAt,omitempty" gorm:"column:ended_at"`
	Status             string     `json:"status" gorm:"column:status"`
	DurationSeconds    int64      `json:"duration" gorm:"column:duration_seconds"`
	EndReason          string     `json:"endReason,omitempty" gorm:"column:end_reason"`
	UpdatedAt          time.Time  `json:"-" gorm:"column:updated_at"`
}

func (CallRecord) TableName() string { return "chat_calls" }

type CallTransition struct {
	Call            CallRecord
	Audience        []string
	ShouldBroadcast bool
}

type CallService struct{}

var CallServiceInstance = &CallService{}

func (s *CallService) ProcessEvent(userid string, event RealtimeEvent) (*CallTransition, error) {
	userid = strings.TrimSpace(userid)
	event.Type = strings.TrimSpace(event.Type)
	event.CallID = strings.TrimSpace(event.CallID)
	event.SourceDeviceID = strings.TrimSpace(event.SourceDeviceID)
	event.MediaType = strings.ToLower(strings.TrimSpace(event.MediaType))
	if event.MediaType == "" {
		event.MediaType = "audio"
	}
	if event.MediaType != "audio" && event.MediaType != "video" {
		return nil, errors.New(ErrInvalidInput)
	}
	if userid == "" || event.CallID == "" || len(event.CallID) > 128 || event.ConversationID == 0 {
		return nil, errors.New(ErrInvalidInput)
	}
	if isCallControlType(event.Type) && event.SourceDeviceID == "" {
		return nil, errors.New(ErrInvalidInput)
	}
	if (event.Type == "call.offer" || event.Type == "call.answer" || event.Type == "call.ice") && len(event.Signal) == 0 {
		return nil, errors.New(ErrInvalidInput)
	}
	db, err := ChatServiceInstance.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	if event.Type == "call.invite" {
		return s.createCall(db, userid, event)
	}

	var call CallRecord
	if err := db.Where("call_id = ? AND conversation_id = ?", event.CallID, event.ConversationID).Take(&call).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrCallNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	if userid != call.CallerUserid && userid != call.CalleeUserid {
		return nil, errors.New(ErrChatNoPermission)
	}
	s.expireCallIfStale(db, &call, time.Now().UTC())

	switch event.Type {
	case "call.accept":
		if userid != call.CalleeUserid || event.SourceDeviceID == "" {
			return nil, errors.New(ErrChatNoPermission)
		}
		now := time.Now().UTC()
		result := db.Model(&CallRecord{}).
			Where("call_id = ? AND status = ?", call.CallID, "ringing").
			Updates(map[string]interface{}{
				"status": "accepted", "answered_at": now,
				"accepted_by_device_id": event.SourceDeviceID, "updated_at": now,
			})
		if result.Error != nil {
			return nil, errors.New(ErrSystem)
		}
		if result.RowsAffected == 0 {
			_ = db.Where("call_id = ?", call.CallID).Take(&call).Error
			if call.Status == "accepted" && call.AcceptedByDeviceID == event.SourceDeviceID {
				return s.transition(call, userid, false, true), nil
			}
			return nil, errors.New(ErrCallConflict)
		}
		_ = db.Where("call_id = ?", call.CallID).Take(&call).Error
		return s.transition(call, userid, true, true), nil

	case "call.reject", "call.busy":
		if userid != call.CalleeUserid {
			return nil, errors.New(ErrChatNoPermission)
		}
		status := strings.TrimPrefix(event.Type, "call.")
		return s.finish(db, call, userid, []string{"ringing"}, status, status)

	case "call.cancel":
		if userid != call.CallerUserid {
			return nil, errors.New(ErrChatNoPermission)
		}
		return s.finish(db, call, userid, []string{"ringing", "accepted", "connecting"}, "canceled", "caller_canceled")

	case "call.end":
		status := "failed"
		reason := "ended_before_connected"
		if call.Status == "active" {
			status = "completed"
			reason = "hangup"
		}
		return s.finish(db, call, userid, []string{"accepted", "connecting", "active"}, status, reason)

	case "call.offer":
		if userid != call.CallerUserid {
			return nil, errors.New(ErrChatNoPermission)
		}
		return s.advance(db, call, userid, "accepted", "connecting")

	case "call.answer":
		if userid != call.CalleeUserid {
			return nil, errors.New(ErrChatNoPermission)
		}
		return s.advance(db, call, userid, "connecting", "active")

	case "call.ice":
		if call.Status != "accepted" && call.Status != "connecting" && call.Status != "active" {
			return nil, errors.New(ErrCallInvalidTransition)
		}
		return s.transition(call, userid, true, false), nil
	default:
		return nil, errors.New(ErrInvalidInput)
	}
}

func (s *CallService) createCall(db *gorm.DB, userid string, event RealtimeEvent) (*CallTransition, error) {
	recipients, err := ChatServiceInstance.DirectCallRecipients(userid, event.ConversationID)
	if err != nil {
		return nil, err
	}
	if len(recipients) != 1 {
		return nil, errors.New(ErrChatNoPermission)
	}
	now := time.Now().UTC()
	call := CallRecord{
		CallID: event.CallID, ConversationID: event.ConversationID,
		CallerUserid: userid, CalleeUserid: recipients[0],
		MediaType: event.MediaType,
		StartedAt: now, Status: "ringing", UpdatedAt: now,
	}
	result := db.Clauses(clause.OnConflict{DoNothing: true}).Create(&call)
	if result.Error != nil {
		return nil, errors.New(ErrSystem)
	}
	if result.RowsAffected == 0 {
		var existing CallRecord
		if err := db.Where("call_id = ?", event.CallID).Take(&existing).Error; err != nil {
			return nil, errors.New(ErrSystem)
		}
		if existing.ConversationID != event.ConversationID || existing.CallerUserid != userid {
			return nil, errors.New(ErrCallConflict)
		}
		return &CallTransition{Call: existing, Audience: []string{existing.CalleeUserid}, ShouldBroadcast: false}, nil
	}
	return &CallTransition{Call: call, Audience: recipients, ShouldBroadcast: true}, nil
}

func (s *CallService) advance(db *gorm.DB, call CallRecord, userid, from, to string) (*CallTransition, error) {
	now := time.Now().UTC()
	result := db.Model(&CallRecord{}).Where("call_id = ? AND status = ?", call.CallID, from).
		Updates(map[string]interface{}{"status": to, "updated_at": now})
	if result.Error != nil {
		return nil, errors.New(ErrSystem)
	}
	if result.RowsAffected == 0 {
		_ = db.Where("call_id = ?", call.CallID).Take(&call).Error
		if call.Status == to {
			return s.transition(call, userid, false, false), nil
		}
		return nil, errors.New(ErrCallInvalidTransition)
	}
	call.Status = to
	call.UpdatedAt = now
	return s.transition(call, userid, true, false), nil
}

func (s *CallService) finish(db *gorm.DB, call CallRecord, userid string, allowed []string, status, reason string) (*CallTransition, error) {
	now := time.Now().UTC()
	duration := int64(0)
	if call.AnsweredAt != nil {
		duration = int64(now.Sub(*call.AnsweredAt).Seconds())
		if duration < 0 {
			duration = 0
		}
	}
	result := db.Model(&CallRecord{}).Where("call_id = ? AND status IN ?", call.CallID, allowed).
		Updates(map[string]interface{}{
			"status": status, "ended_at": now, "duration_seconds": duration,
			"end_reason": reason, "updated_at": now,
		})
	if result.Error != nil {
		return nil, errors.New(ErrSystem)
	}
	if result.RowsAffected == 0 {
		_ = db.Where("call_id = ?", call.CallID).Take(&call).Error
		if call.EndedAt != nil {
			return s.transition(call, userid, false, true), nil
		}
		return nil, errors.New(ErrCallInvalidTransition)
	}
	call.Status, call.EndReason, call.EndedAt, call.DurationSeconds = status, reason, &now, duration
	return s.transition(call, userid, true, true), nil
}

func (s *CallService) transition(call CallRecord, actor string, broadcast, includeAllDevices bool) *CallTransition {
	audience := []string{call.CalleeUserid}
	if actor == call.CalleeUserid {
		audience = []string{call.CallerUserid}
	}
	if includeAllDevices {
		audience = []string{call.CallerUserid, call.CalleeUserid}
	}
	return &CallTransition{Call: call, Audience: audience, ShouldBroadcast: broadcast}
}

func (s *CallService) History(userid string, limit int) ([]CallRecord, error) {
	db, err := ChatServiceInstance.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}
	var calls []CallRecord
	if err := db.Where("caller_userid = ? OR callee_userid = ?", userid, userid).
		Order("started_at DESC").Limit(limit).Find(&calls).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	return calls, nil
}

func (s *CallService) Get(userid, callID string) (*CallRecord, error) {
	db, err := ChatServiceInstance.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	var call CallRecord
	if err := db.Where("call_id = ? AND (caller_userid = ? OR callee_userid = ?)", strings.TrimSpace(callID), userid, userid).Take(&call).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrCallNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	return &call, nil
}

func isCallControlType(eventType string) bool {
	switch eventType {
	case "call.invite", "call.accept", "call.reject", "call.busy", "call.cancel", "call.end":
		return true
	default:
		return false
	}
}

func (s *CallService) StartReaper(ctx context.Context, configuration config.WebRTCConfiguration) {
	go func() {
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case now := <-ticker.C:
				if db, err := ChatServiceInstance.chatDB(); err == nil {
					s.expireStaleCallsWithConfig(db, now.UTC(), configuration)
				}
			}
		}
	}()
}

func (s *CallService) expireStaleCalls(db *gorm.DB, now time.Time) {
	configuration := config.WebRTCConfiguration{}
	if current := config.GetConfig(); current != nil {
		configuration = current.WebRTC
	}
	s.expireStaleCallsWithConfig(db, now, configuration)
}

func (s *CallService) expireCallIfStale(db *gorm.DB, call *CallRecord, now time.Time) {
	configuration := config.WebRTCConfiguration{}
	if current := config.GetConfig(); current != nil {
		configuration = current.WebRTC
	}
	status, reason := "", ""
	duration := call.DurationSeconds
	switch {
	case call.Status == "ringing" && call.StartedAt.Before(now.Add(-durationSeconds(configuration.CallRingTimeoutSeconds, 45*time.Second))):
		status, reason = "missed", "timeout"
	case (call.Status == "accepted" || call.Status == "connecting") && call.AnsweredAt != nil && call.AnsweredAt.Before(now.Add(-durationSeconds(configuration.CallConnectTimeoutSeconds, 60*time.Second))):
		status, reason = "failed", "connection_timeout"
	case call.Status == "active" && call.AnsweredAt != nil && call.AnsweredAt.Before(now.Add(-durationSeconds(configuration.CallMaximumDurationSeconds, 4*time.Hour))):
		status, reason = "completed", "maximum_duration"
		duration = int64(durationSeconds(configuration.CallMaximumDurationSeconds, 4*time.Hour).Seconds())
	}
	if status == "" {
		return
	}
	result := db.Model(&CallRecord{}).Where("call_id = ? AND status = ?", call.CallID, call.Status).
		Updates(map[string]interface{}{
			"status": status, "ended_at": now, "duration_seconds": duration,
			"end_reason": reason, "updated_at": now,
		})
	if result.Error == nil && result.RowsAffected > 0 {
		call.Status, call.EndReason, call.EndedAt, call.DurationSeconds = status, reason, &now, duration
	} else {
		_ = db.Where("call_id = ?", call.CallID).Take(call).Error
	}
}

func (s *CallService) expireStaleCallsWithConfig(db *gorm.DB, now time.Time, configuration config.WebRTCConfiguration) {
	ringTimeout := durationSeconds(configuration.CallRingTimeoutSeconds, 45*time.Second)
	connectTimeout := durationSeconds(configuration.CallConnectTimeoutSeconds, 60*time.Second)
	maximumDuration := durationSeconds(configuration.CallMaximumDurationSeconds, 4*time.Hour)
	_ = db.Model(&CallRecord{}).Where("status = ? AND started_at < ?", "ringing", now.Add(-ringTimeout)).
		Updates(map[string]interface{}{"status": "missed", "ended_at": now, "end_reason": "timeout", "updated_at": now}).Error
	_ = db.Model(&CallRecord{}).Where("status IN ? AND answered_at < ?", []string{"accepted", "connecting"}, now.Add(-connectTimeout)).
		Updates(map[string]interface{}{"status": "failed", "ended_at": now, "end_reason": "connection_timeout", "updated_at": now}).Error
	_ = db.Model(&CallRecord{}).Where("status = ? AND answered_at < ?", "active", now.Add(-maximumDuration)).
		Updates(map[string]interface{}{"status": "completed", "ended_at": now, "duration_seconds": int64(maximumDuration.Seconds()), "end_reason": "maximum_duration", "updated_at": now}).Error
}

func durationSeconds(value int, fallback time.Duration) time.Duration {
	if value <= 0 {
		return fallback
	}
	return time.Duration(value) * time.Second
}
