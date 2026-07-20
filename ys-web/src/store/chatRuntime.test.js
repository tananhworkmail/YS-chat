import assert from "node:assert/strict";
import test from "node:test";
import {
  canTransitionCallState,
  applyMessageReceipt,
  attachClientMessageId,
  createClientMessageId,
  isRetryableSendError,
  mergeCatchUpCursor,
  messageClientId,
  messageDedupeKey,
  normalizeReactionGroups,
  normalizeRealtimeEvent,
  shouldMarkReadForVisibility,
  seedMissingConversationCursors,
  snapshotCatchUpCursors,
} from "./chatRuntime.js";

test("call state machine rejects late and out-of-order transitions", () => {
  assert.equal(canTransitionCallState("idle", "incoming"), true);
  assert.equal(canTransitionCallState("incoming", "connecting"), true);
  assert.equal(canTransitionCallState("connecting", "active"), true);
  assert.equal(canTransitionCallState("active", "idle"), true);
  assert.equal(canTransitionCallState("idle", "active"), false);
  assert.equal(canTransitionCallState("idle", "connecting"), false);
  assert.equal(canTransitionCallState("outgoing", "incoming"), false);
});

test("client message IDs are UUID v4 values", () => {
  const first = createClientMessageId();
  const second = createClientMessageId();
  assert.match(first, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  assert.notEqual(first, second);
});

test("read acknowledgements are allowed only for visible documents", () => {
  assert.equal(shouldMarkReadForVisibility("visible"), true);
  assert.equal(shouldMarkReadForVisibility("hidden"), false);
  assert.equal(shouldMarkReadForVisibility("prerender"), false);
});

test("normalizes versioned payload and legacy realtime frames", () => {
  const message = { id: 42, conversationId: 7 };
  const envelope = normalizeRealtimeEvent({
    type: "message.updated",
    event_id: "evt-1",
    server_timestamp: "2026-07-15T00:00:00Z",
    conversation_id: 7,
    message_id: 42,
    version: 1,
    payload: { message },
  });
  assert.equal(envelope.eventId, "evt-1");
  assert.equal(envelope.conversationId, 7);
  assert.equal(envelope.message, message);

  const legacy = normalizeRealtimeEvent({ type: "chat.message.created", message });
  assert.equal(legacy.message, message);

  const videoInvite = normalizeRealtimeEvent({
    type: "call.invite",
    payload: { callId: "video-1", mediaType: "video" },
  });
  assert.equal(videoInvite.mediaType, "video");
});

test("accepts camelCase and snake_case client message IDs", () => {
  assert.equal(messageClientId({ clientMessageId: "one" }), "one");
  assert.equal(messageClientId({ client_message_id: "two" }), "two");
});

test("message dedupe key is scoped by sender and legacy success can inherit the pending ID", () => {
  const first = { senderUserid: "u1", clientMessageId: "same-id" };
  const second = { senderUserid: "u2", clientMessageId: "same-id" };
  assert.notEqual(messageDedupeKey(first), messageDedupeKey(second));
  assert.equal(messageDedupeKey(first), messageDedupeKey({ sender_userid: "u1", client_message_id: "same-id" }));
  assert.deepEqual(attachClientMessageId({ id: 9, senderUserid: "u1" }, "pending-id"), {
    id: 9,
    senderUserid: "u1",
    clientMessageId: "pending-id",
  });
  assert.equal(attachClientMessageId(first, "different"), first);
});

test("automatic send retry is limited to transient failures", () => {
  assert.equal(isRetryableSendError({ request: {} }), true);
  assert.equal(isRetryableSendError({ code: "ECONNABORTED", response: { status: 400 } }), true);
  assert.equal(isRetryableSendError({ response: { status: 408 } }), true);
  assert.equal(isRetryableSendError({ response: { status: 429 } }), true);
  assert.equal(isRetryableSendError({ response: { status: 503 } }), true);
  assert.equal(isRetryableSendError({ response: { status: 400 } }), false);
  assert.equal(isRetryableSendError({ response: { status: 409 } }), false);
});

test("groups flat reactions uniquely per user and emoji", () => {
  const groups = normalizeReactionGroups({
    reactions: [
      { emoji: "👍", userid: "u1" },
      { emoji: "👍", userid: "u1" },
      { emoji: "👍", userid: "u2" },
    ],
  }, "u2");
  assert.deepEqual(groups, [{ emoji: "👍", count: 2, userids: ["u1", "u2"], users: [], reactedByMe: true }]);
});

test("keeps reaction member names for the group detail popover", () => {
  const groups = normalizeReactionGroups({
    reactions: [{
      emoji: "❤️",
      count: 2,
      userids: ["u1", "u2"],
      users: [
        { userid: "u1", fullname: "An", avatar: "/a.png" },
        { userid: "u2", fullname: "Binh" },
      ],
    }],
  }, "u1");
  assert.equal(groups[0].users[0].fullname, "An");
  assert.equal(groups[0].users[1].fullname, "Binh");
  assert.equal(groups[0].reactedByMe, true);
});

test("snapshots every conversation cursor before catch-up and does not retain mutable references", () => {
  const cursors = { 1: { afterSequence: 10, afterMessageId: 100 } };
  const snapshots = snapshotCatchUpCursors([
    { id: 1, lastMessage: { id: 101, serverSequence: 11 } },
    { id: 2, lastMessage: { id: 200, serverSequence: 20 } },
  ], cursors);

  cursors[1].afterSequence = 999;
  assert.deepEqual(snapshots, [
    { conversationId: 1, cursor: { afterSequence: 10, afterMessageId: 100 } },
    { conversationId: 2, cursor: { afterSequence: 0, afterMessageId: 0 } },
  ]);
  assert.deepEqual(
    mergeCatchUpCursor(snapshots[0].cursor, { afterSequence: 12, afterMessageId: 102 }),
    { afterSequence: 12, afterMessageId: 102 },
  );
});

test("cursor baselines are seeded once before realtime and never overwritten by newer summaries", () => {
  const seeded = seedMissingConversationCursors([
    { id: 1, lastMessage: { id: 100, serverSequence: 10 } },
    { id: 2, lastMessage: { id: 200, serverSequence: 20 } },
    { id: 3, lastMessage: { id: 300, serverSequence: 30 } },
  ], {
    1: { afterSequence: 8, afterMessageId: 80 },
    3: { afterSequence: 0, afterMessageId: 0 },
  });
  assert.deepEqual(seeded, {
    1: { afterSequence: 8, afterMessageId: 80 },
    2: { afterSequence: 20, afterMessageId: 200 },
    3: { afterSequence: 0, afterMessageId: 0 },
  });

  const afterFallbackSummary = seedMissingConversationCursors([
    { id: 1, lastMessage: { id: 999, serverSequence: 99 } },
  ], seeded);
  assert.deepEqual(afterFallbackSummary[1], { afterSequence: 8, afterMessageId: 80 });
});

test("group receipt state advances only after every recipient reaches that state", () => {
  const base = {
    id: 1,
    status: "sent",
    receiptSummary: { totalRecipients: 3, deliveredRecipients: 0, readRecipients: 0 },
    receipts: [],
  };
  const oneDelivered = applyMessageReceipt(base, { kind: "delivered", userid: "u1", totalRecipients: 3, occurredAt: "t1" });
  assert.equal(oneDelivered.status, "sent");
  const twoDelivered = applyMessageReceipt(oneDelivered, { kind: "delivered", userid: "u2", totalRecipients: 3, occurredAt: "t2" });
  assert.equal(twoDelivered.status, "sent");
  const allDelivered = applyMessageReceipt(twoDelivered, { kind: "delivered", userid: "u3", totalRecipients: 3, occurredAt: "t3" });
  assert.equal(allDelivered.status, "delivered");

  const oneRead = applyMessageReceipt(allDelivered, { kind: "read", userid: "u1", totalRecipients: 3, occurredAt: "t4" });
  assert.equal(oneRead.status, "delivered");
  const twoRead = applyMessageReceipt(oneRead, { kind: "read", userid: "u2", totalRecipients: 3, occurredAt: "t5" });
  assert.equal(twoRead.status, "delivered");
  const allRead = applyMessageReceipt(twoRead, { kind: "read", userid: "u3", totalRecipients: 3, occurredAt: "t6" });
  assert.equal(allRead.status, "read");
});
