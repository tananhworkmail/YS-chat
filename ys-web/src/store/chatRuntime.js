const hasOwn = (value, key) => Object.prototype.hasOwnProperty.call(value || {}, key);

export const shouldMarkReadForVisibility = (visibilityState) =>
  visibilityState === undefined || visibilityState === "visible";

export const createClientMessageId = () => {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();

  const bytes = new Uint8Array(16);
  if (globalThis.crypto?.getRandomValues) {
    globalThis.crypto.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Math.floor(Math.random() * 256);
    }
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
};

export const normalizeRealtimeEvent = (rawEvent = {}) => {
  const payload = rawEvent?.payload && typeof rawEvent.payload === "object" ? rawEvent.payload : {};
  const value = (camelKey, snakeKey) => {
    if (hasOwn(rawEvent, camelKey)) return rawEvent[camelKey];
    if (hasOwn(rawEvent, snakeKey)) return rawEvent[snakeKey];
    if (hasOwn(payload, camelKey)) return payload[camelKey];
    return payload[snakeKey];
  };

  return {
    ...rawEvent,
    type: rawEvent.type || rawEvent.eventType || rawEvent.event_type || payload.type || "",
    eventId: value("eventId", "event_id") || "",
    serverTimestamp: value("serverTimestamp", "server_timestamp") || rawEvent.timestamp || payload.timestamp || "",
    conversationId: value("conversationId", "conversation_id"),
    messageId: value("messageId", "message_id"),
    version: Number(value("version", "version") || 1),
    payload,
    message: payload.message || rawEvent.message || null,
    userid: value("userid", "user_id"),
    readerUserid: value("readerUserid", "reader_userid"),
    lastReadMessageId: value("lastReadMessageId", "last_read_message_id"),
    deliveredMessageId: value("deliveredMessageId", "delivered_message_id") || value("messageId", "message_id"),
    emoji: value("emoji", "emoji"),
    isOnline: value("isOnline", "is_online"),
  };
};

export const messageClientId = (message = {}) =>
  message.clientMessageId || message.client_message_id || "";

export const messageDedupeKey = (message = {}) => {
  const senderUserid = String(message.senderUserid || message.sender_userid || "").trim();
  const clientMessageId = String(messageClientId(message) || "").trim();
  return senderUserid && clientMessageId ? JSON.stringify([senderUserid, clientMessageId]) : "";
};

export const attachClientMessageId = (message = {}, clientMessageId = "") => {
  if (!clientMessageId || messageClientId(message)) return message;
  return { ...message, clientMessageId };
};

export const isRetryableSendError = (error = {}) => {
  const status = Number(error?.response?.status || 0);
  if (!error?.response) return true;
  if (["ECONNABORTED", "ETIMEDOUT"].includes(String(error?.code || "").toUpperCase())) return true;
  return status === 408 || status === 429 || status >= 500;
};

export const messageSequence = (message = {}) =>
  Number(message.serverSequence || message.server_sequence || 0);

export const messageDeliveryState = (message = {}) => {
  if (message._sendState === "failed") return "failed";
  if (message._sendState === "sending") return "sending";
  const state = String(message.status || message.state || message.deliveryState || message.delivery_state || "sent")
    .toLowerCase();
  return ["sending", "failed", "sent", "delivered", "read"].includes(state) ? state : "sent";
};

export const snapshotCatchUpCursors = (conversations = [], cursorState = {}) => {
  const snapshots = [];
  const seenConversationIds = new Set();

  conversations.forEach((conversation) => {
    if (conversation?.id === undefined || conversation?.id === null) return;
    const conversationId = conversation.id;
    const key = String(conversationId);
    const stored = cursorState[key] || {};
    snapshots.push({
      conversationId,
      cursor: {
        afterSequence: Number(stored.afterSequence || 0),
        afterMessageId: Number(stored.afterMessageId || 0),
      },
    });
    seenConversationIds.add(key);
  });

  Object.entries(cursorState).forEach(([key, cursor]) => {
    if (seenConversationIds.has(key)) return;
    const numericId = Number(key);
    snapshots.push({
      conversationId: Number.isFinite(numericId) && numericId > 0 ? numericId : key,
      cursor: {
        afterSequence: Number(cursor?.afterSequence || 0),
        afterMessageId: Number(cursor?.afterMessageId || 0),
      },
    });
  });

  return snapshots;
};

export const seedMissingConversationCursors = (conversations = [], cursorState = {}) => {
  const next = Object.fromEntries(
    Object.entries(cursorState).map(([key, cursor]) => [key, {
      afterSequence: Number(cursor?.afterSequence || 0),
      afterMessageId: Number(cursor?.afterMessageId || 0),
    }]),
  );
  conversations.forEach((conversation) => {
    if (conversation?.id === undefined || conversation?.id === null) return;
    const key = String(conversation.id);
    if (Object.prototype.hasOwnProperty.call(next, key)) return;
    const lastMessage = conversation.lastMessage || {};
    next[key] = {
      afterSequence: messageSequence(lastMessage),
      afterMessageId: Number(lastMessage.id || 0),
    };
  });
  return next;
};

export const mergeCatchUpCursor = (first = {}, second = {}) => ({
  afterSequence: Math.max(Number(first.afterSequence || 0), Number(second.afterSequence || 0)),
  afterMessageId: Math.max(Number(first.afterMessageId || 0), Number(second.afterMessageId || 0)),
});

const receiptUserid = (value) => String(value?.userid || value || "").trim();

const receiptUseridSet = (values = []) => new Set(values.map(receiptUserid).filter(Boolean));

export const applyMessageReceipt = (message = {}, options = {}) => {
  const kind = options.kind === "read" ? "read" : "delivered";
  const userid = String(options.userid || "").trim();
  const occurredAt = options.occurredAt || new Date().toISOString();
  const summary = message.receiptSummary || message.receipt_summary || {};
  const receipts = (message.receipts || []).map((receipt) => ({ ...receipt }));
  const deliveredTo = receiptUseridSet(message.deliveredTo || message.delivered_to || []);
  const readBy = receiptUseridSet(message.readBy || message.read_by || []);

  receipts.forEach((receipt) => {
    const member = receiptUserid(receipt);
    if (!member) return;
    if (receipt.deliveredAt || receipt.delivered_at || receipt.readAt || receipt.read_at) deliveredTo.add(member);
    if (receipt.readAt || receipt.read_at) readBy.add(member);
  });

  const wasDelivered = userid ? deliveredTo.has(userid) : true;
  const wasRead = userid ? readBy.has(userid) : true;
  if (userid) {
    let receipt = receipts.find((item) => receiptUserid(item) === userid);
    if (!receipt) {
      receipt = { userid };
      receipts.push(receipt);
    }
    if (!receipt.deliveredAt && !receipt.delivered_at) receipt.deliveredAt = occurredAt;
    deliveredTo.add(userid);
    if (kind === "read") {
      if (!receipt.readAt && !receipt.read_at) receipt.readAt = occurredAt;
      readBy.add(userid);
    }
  }

  const summaryDelivered = Number(summary.deliveredRecipients ?? summary.delivered_recipients ?? 0);
  const summaryRead = Number(summary.readRecipients ?? summary.read_recipients ?? 0);
  let deliveredRecipients = Math.max(deliveredTo.size, summaryDelivered + (userid && !wasDelivered ? 1 : 0));
  let readRecipients = Math.max(readBy.size, summaryRead + (kind === "read" && userid && !wasRead ? 1 : 0));
  deliveredRecipients = Math.max(deliveredRecipients, readRecipients);

  const totalRecipients = Number(summary.totalRecipients ?? summary.total_recipients ?? 0)
    || Number(options.totalRecipients || 0)
    || receipts.length;
  if (totalRecipients > 0) {
    deliveredRecipients = Math.min(deliveredRecipients, totalRecipients);
    readRecipients = Math.min(readRecipients, totalRecipients);
  }

  let status = "sent";
  if (totalRecipients > 0 && readRecipients >= totalRecipients) status = "read";
  else if (totalRecipients > 0 && deliveredRecipients >= totalRecipients) status = "delivered";

  return {
    ...message,
    status,
    state: status,
    receipts,
    deliveredTo: Array.from(deliveredTo),
    readBy: Array.from(readBy),
    deliveredCount: deliveredRecipients,
    readCount: readRecipients,
    receiptSummary: {
      totalRecipients,
      deliveredRecipients,
      readRecipients,
    },
  };
};

export const normalizeReactionGroups = (message = {}, currentUserid = "") => {
  const source = message.reactionSummary || message.reaction_summary || message.reactions || [];
  const groups = new Map();

  source.forEach((reaction) => {
    const emoji = String(reaction?.emoji || "").trim();
    if (!emoji) return;
    if (!groups.has(emoji)) {
      groups.set(emoji, { emoji, count: 0, userids: [], users: [], reactedByMe: false });
    }
    const group = groups.get(emoji);
    const reactionUsers = Array.isArray(reaction.users) ? reaction.users : [];
    reactionUsers.forEach((user) => {
      const userid = String(user?.userid || user?.userId || user || "").trim();
      if (!userid) return;
      if (!group.users.some((entry) => entry.userid === userid)) {
        group.users.push({
          userid,
          fullname: String(user?.fullname || user?.fullName || user?.name || userid),
          avatar: String(user?.avatar || ""),
        });
      }
    });
    const userids = reaction.userids || reaction.userIds || reactionUsers.map((user) => user?.userid || user?.userId || user) || [];
    const userid = reaction.userid || reaction.userId;
    const members = userids.length ? userids : userid ? [userid] : [];
    members.forEach((member) => {
      const normalized = String(member || "");
      if (normalized && !group.userids.includes(normalized)) group.userids.push(normalized);
    });
    group.users.forEach((user) => {
      if (!group.userids.includes(user.userid)) group.userids.push(user.userid);
    });
    const explicitCount = Number(reaction.count || reaction.reactionCount || 0);
    group.count = Math.max(group.count, explicitCount, group.userids.length);
    group.reactedByMe = group.reactedByMe
      || Boolean(reaction.reactedByMe || reaction.mine)
      || group.userids.includes(String(currentUserid || ""));
  });

  return Array.from(groups.values()).map((group) => ({
    ...group,
    count: Math.max(1, group.count),
  }));
};
