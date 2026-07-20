package services

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"gorm.io/gorm"
)

type ReminderService struct{}

var ReminderServiceInstance = &ReminderService{}

const (
	ReminderRepeatNone    = "none"
	ReminderRepeatDaily   = "daily"
	ReminderRepeatWeekly  = "weekly"
	ReminderRepeatMonthly = "monthly"
)

func (s *ReminderService) Create(userid string, conversationID uint64, input request.CreateReminderRequest) (*types.ChatReminder, error) {
	db, err := ChatServiceInstance.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	title := strings.TrimSpace(input.Title)
	remindAt := input.RemindAt.UTC()
	repeatType := normalizeReminderRepeatType(input.RepeatType)
	if title == "" || utf8.RuneCountInString(title) > 240 || remindAt.Before(time.Now().UTC().Add(3*time.Second)) || remindAt.After(time.Now().UTC().AddDate(1, 0, 0)) {
		return nil, errors.New(ErrInvalidInput)
	}
	isMember, err := ChatServiceInstance.isConversationMember(db, conversationID, userid)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	if !isMember {
		return nil, errors.New(ErrChatNoPermission)
	}
	record := chatReminderRecord{ConversationID: conversationID, CreatorUserid: userid, Title: title, RemindAt: remindAt, RepeatType: repeatType, Status: "scheduled", CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC()}
	if err := db.Table("chat_reminders").Create(&record).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	reminder := s.toReminder(db, record)
	RealtimeHubInstance.BroadcastToUsers(s.memberUserids(db, conversationID), RealtimeEvent{Type: "reminder.created", ConversationID: conversationID, Payload: reminder})
	return reminder, nil
}

func (s *ReminderService) List(userid string, conversationID uint64) ([]types.ChatReminder, error) {
	db, err := ChatServiceInstance.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	isMember, err := ChatServiceInstance.isConversationMember(db, conversationID, userid)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	if !isMember {
		return nil, errors.New(ErrChatNoPermission)
	}
	var records []chatReminderRecord
	if err := db.Table("chat_reminders").Where("conversation_id = ? AND status = ?", conversationID, "scheduled").Order("remind_at ASC, id ASC").Find(&records).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	result := make([]types.ChatReminder, 0, len(records))
	for _, record := range records {
		result = append(result, *s.toReminder(db, record))
	}
	return result, nil
}

func (s *ReminderService) Cancel(userid string, reminderID uint64) error {
	db, err := ChatServiceInstance.chatDB()
	if err != nil {
		return errors.New(ErrSystem)
	}
	var record chatReminderRecord
	if err := db.Table("chat_reminders").Where("id = ?", reminderID).Take(&record).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New(ErrChatMessageNotFound)
		}
		return errors.New(ErrSystem)
	}
	if record.CreatorUserid != userid {
		return errors.New(ErrChatNoPermission)
	}
	result := db.Table("chat_reminders").Where("id = ? AND status = ?", reminderID, "scheduled").Updates(map[string]interface{}{"status": "canceled", "updated_at": time.Now().UTC()})
	if result.Error != nil {
		return errors.New(ErrSystem)
	}
	if result.RowsAffected > 0 {
		RealtimeHubInstance.BroadcastToUsers(s.memberUserids(db, record.ConversationID), RealtimeEvent{Type: "reminder.canceled", ConversationID: record.ConversationID, Payload: map[string]interface{}{"id": reminderID, "conversationId": record.ConversationID}})
	}
	return nil
}

func (s *ReminderService) StartScheduler(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case now := <-ticker.C:
				if db, err := ChatServiceInstance.chatDB(); err == nil {
					s.fireDue(db, now.UTC())
				}
			}
		}
	}()
}

func (s *ReminderService) fireDue(db *gorm.DB, now time.Time) {
	var records []chatReminderRecord
	if err := db.Table("chat_reminders").Where("status = ? AND remind_at <= ?", "scheduled", now).Order("remind_at ASC").Limit(100).Find(&records).Error; err != nil {
		return
	}
	for _, record := range records {
		result := db.Table("chat_reminders").Where("id = ? AND status = ?", record.ID, "scheduled").Updates(map[string]interface{}{"status": "fired", "fired_at": now, "updated_at": now})
		if result.Error != nil || result.RowsAffected == 0 {
			continue
		}
		record.Status = "fired"
		record.FiredAt = &now
		reminder := s.toReminder(db, record)
		audience := s.memberUserids(db, record.ConversationID)
		RealtimeHubInstance.BroadcastToUsers(audience, RealtimeEvent{Type: "reminder.due", ConversationID: record.ConversationID, Payload: reminder})
		PushServiceInstance.SendReminderNotification(db, reminder)
		if nextRemindAt, ok := nextReminderTime(record.RemindAt, record.RepeatType, now); ok {
			update := map[string]interface{}{"status": "scheduled", "remind_at": nextRemindAt, "updated_at": now}
			if err := db.Table("chat_reminders").Where("id = ?", record.ID).Updates(update).Error; err != nil {
				continue
			}
			record.Status = "scheduled"
			record.RemindAt = nextRemindAt
			record.FiredAt = &now
			RealtimeHubInstance.BroadcastToUsers(audience, RealtimeEvent{Type: "reminder.updated", ConversationID: record.ConversationID, Payload: s.toReminder(db, record)})
		}
	}
}

func (s *ReminderService) memberUserids(db *gorm.DB, conversationID uint64) []string {
	var userids []string
	_ = db.Table("chat_members").Where("conversation_id = ?", conversationID).Pluck("userid", &userids).Error
	return userids
}

func (s *ReminderService) toReminder(db *gorm.DB, record chatReminderRecord) *types.ChatReminder {
	name, _ := ChatServiceInstance.userDisplayName(db, record.CreatorUserid)
	if name == "" {
		name = record.CreatorUserid
	}
	repeatType := normalizeReminderRepeatType(record.RepeatType)
	return &types.ChatReminder{ID: record.ID, ConversationID: record.ConversationID, CreatorUserid: record.CreatorUserid, CreatorName: name, Title: record.Title, RemindAt: record.RemindAt, RepeatType: repeatType, Status: record.Status, FiredAt: record.FiredAt, CreatedAt: record.CreatedAt}
}

func normalizeReminderRepeatType(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case ReminderRepeatDaily, ReminderRepeatWeekly, ReminderRepeatMonthly:
		return strings.ToLower(strings.TrimSpace(value))
	default:
		return ReminderRepeatNone
	}
}

func nextReminderTime(remindAt time.Time, repeatType string, now time.Time) (time.Time, bool) {
	repeatType = normalizeReminderRepeatType(repeatType)
	if repeatType == ReminderRepeatNone {
		return time.Time{}, false
	}
	next := remindAt
	for i := 0; i < 500 && !next.After(now); i++ {
		switch repeatType {
		case ReminderRepeatDaily:
			next = next.AddDate(0, 0, 1)
		case ReminderRepeatWeekly:
			next = next.AddDate(0, 0, 7)
		case ReminderRepeatMonthly:
			next = addReminderMonth(next)
		}
	}
	if !next.After(now) {
		return time.Time{}, false
	}
	return next, true
}

func addReminderMonth(value time.Time) time.Time {
	year, month, day := value.Date()
	hour, minute, second := value.Clock()
	targetMonth := month + 1
	targetYear := year
	if targetMonth > time.December {
		targetMonth = time.January
		targetYear++
	}
	lastDay := time.Date(targetYear, targetMonth+1, 0, hour, minute, second, value.Nanosecond(), value.Location()).Day()
	if day > lastDay {
		day = lastDay
	}
	return time.Date(targetYear, targetMonth, day, hour, minute, second, value.Nanosecond(), value.Location())
}
