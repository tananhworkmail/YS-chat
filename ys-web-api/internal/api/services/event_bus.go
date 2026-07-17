package services

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"sync"

	"github.com/redis/go-redis/v9"
)

type RealtimeEnvelope struct {
	Userids []string      `json:"userids"`
	Event   RealtimeEvent `json:"event"`
}

// RealtimeEventBus separates websocket delivery from event publication. The
// in-memory implementation is the default; Redis allows every backend
// instance to receive the same envelope when the API is scaled horizontally.
type RealtimeEventBus interface {
	Publish(context.Context, RealtimeEnvelope) error
	Subscribe(func(RealtimeEnvelope)) error
	Close() error
}

type InMemoryRealtimeEventBus struct {
	mu      sync.RWMutex
	handler func(RealtimeEnvelope)
	closed  bool
}

func NewInMemoryRealtimeEventBus() *InMemoryRealtimeEventBus {
	return &InMemoryRealtimeEventBus{}
}

func (b *InMemoryRealtimeEventBus) Subscribe(handler func(RealtimeEnvelope)) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.closed {
		return errors.New("realtime event bus is closed")
	}
	b.handler = handler
	return nil
}

func (b *InMemoryRealtimeEventBus) Publish(_ context.Context, envelope RealtimeEnvelope) error {
	b.mu.RLock()
	handler, closed := b.handler, b.closed
	b.mu.RUnlock()
	if closed {
		return errors.New("realtime event bus is closed")
	}
	if handler != nil {
		handler(envelope)
	}
	return nil
}

func (b *InMemoryRealtimeEventBus) Close() error {
	b.mu.Lock()
	b.closed = true
	b.handler = nil
	b.mu.Unlock()
	return nil
}

type RedisRealtimeEventBus struct {
	client  *redis.Client
	channel string
	ctx     context.Context
	cancel  context.CancelFunc
	mu      sync.Mutex
	pubsub  *redis.PubSub
}

func NewRedisRealtimeEventBus(redisURL, channel string) (*RedisRealtimeEventBus, error) {
	options, err := redis.ParseURL(strings.TrimSpace(redisURL))
	if err != nil {
		return nil, err
	}
	channel = strings.TrimSpace(channel)
	if channel == "" {
		channel = "ys-chat:realtime:v1"
	}
	ctx, cancel := context.WithCancel(context.Background())
	client := redis.NewClient(options)
	if err := client.Ping(ctx).Err(); err != nil {
		cancel()
		_ = client.Close()
		return nil, err
	}
	return &RedisRealtimeEventBus{client: client, channel: channel, ctx: ctx, cancel: cancel}, nil
}

func (b *RedisRealtimeEventBus) Subscribe(handler func(RealtimeEnvelope)) error {
	if handler == nil {
		return errors.New("realtime event handler is required")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.pubsub != nil {
		return errors.New("realtime event bus already subscribed")
	}
	b.pubsub = b.client.Subscribe(b.ctx, b.channel)
	if _, err := b.pubsub.Receive(b.ctx); err != nil {
		_ = b.pubsub.Close()
		b.pubsub = nil
		return err
	}
	go func(pubsub *redis.PubSub) {
		messages := pubsub.Channel()
		for {
			select {
			case <-b.ctx.Done():
				return
			case message, ok := <-messages:
				if !ok {
					return
				}
				var envelope RealtimeEnvelope
				if json.Unmarshal([]byte(message.Payload), &envelope) == nil {
					handler(envelope)
				}
			}
		}
	}(b.pubsub)
	return nil
}

func (b *RedisRealtimeEventBus) Publish(ctx context.Context, envelope RealtimeEnvelope) error {
	payload, err := json.Marshal(envelope)
	if err != nil {
		return err
	}
	return b.client.Publish(ctx, b.channel, payload).Err()
}

func (b *RedisRealtimeEventBus) Close() error {
	b.cancel()
	b.mu.Lock()
	pubsub := b.pubsub
	b.pubsub = nil
	b.mu.Unlock()
	if pubsub != nil {
		_ = pubsub.Close()
	}
	return b.client.Close()
}
