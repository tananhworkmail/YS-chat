import axios from "axios";

const API_URL = import.meta.env.VITE_API_URL || "/api/v1";

const api = axios.create({
  baseURL: API_URL,
  timeout: 15000,
});

const DEVICE_ID_KEY = "ys_device_id";

export const getOrCreateDeviceId = () => {
  const stored = localStorage.getItem(DEVICE_ID_KEY)?.trim();
  if (stored) return stored;
  const generated = globalThis.crypto?.randomUUID?.()
    || `web-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  localStorage.setItem(DEVICE_ID_KEY, generated);
  return generated;
};

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("user_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export const searchUsers = (keyword = "") => {
  return api.get("/chat/users", { params: { keyword } });
};

export const searchChat = (keyword = "", scope = "all", filters = {}) => {
  return api.get("/chat/search", { params: { keyword, scope, ...filters } });
};

export const getContacts = () => {
  return api.get("/chat/contacts");
};

export const addContact = (userid) => {
  return api.post("/chat/contacts", { userid });
};

export const updateContactNickname = (userid, nickname) => {
  return api.put(`/chat/contacts/${encodeURIComponent(userid)}/nickname`, { nickname });
};

export const registerDeviceToken = (token, platform = "web", deviceId = getOrCreateDeviceId()) => {
  return api.post("/chat/devices", { token, platform, deviceId });
};

export const unregisterDeviceToken = (deviceId = getOrCreateDeviceId(), token = "") => {
  return api.delete("/chat/devices", { data: { deviceId, token } });
};

export const getConversations = () => {
  return api.get("/chat/conversations");
};

export const createDirectConversation = (userid) => {
  return api.post("/chat/conversations/direct", { userid });
};

export const createGroupConversation = (name, memberUserids) => {
  return api.post("/chat/conversations/group", { name, memberUserids });
};

export const updateConversationSettings = (conversationId, payload) => {
  return api.put(`/chat/conversations/${conversationId}/settings`, payload);
};

// These settings belong to the authenticated member, never to the conversation
// itself. Keeping them on a separate endpoint prevents an older client from
// accidentally changing another member's preferences.
export const updateConversationUserSettings = (conversationId, payload) => {
  return api.patch(`/chat/conversations/${conversationId}/user-settings`, payload);
};

export const addConversationMembers = (conversationId, userids) => {
  return api.post(`/chat/conversations/${conversationId}/members`, { userids });
};

export const removeConversationMember = (conversationId, userid) => {
  return api.delete(`/chat/conversations/${conversationId}/members/${encodeURIComponent(userid)}`);
};

export const updateConversationMemberNickname = (conversationId, userid, nickname) => {
  return api.put(`/chat/conversations/${conversationId}/members/${encodeURIComponent(userid)}/nickname`, { nickname });
};

export const getMessages = (conversationId, params = {}) => {
  return api.get(`/chat/conversations/${conversationId}/messages`, { params });
};

export const getMessageCatchUp = (conversationId, params = {}) => {
  return api.get(`/chat/conversations/${conversationId}/messages/catch-up`, { params });
};

export const searchConversationMessages = (conversationId, params = {}) => {
  return api.get(`/chat/conversations/${conversationId}/messages/search`, { params });
};

export const sendMessage = (conversationId, payload) => {
  return api.post(`/chat/conversations/${conversationId}/messages`, payload);
};

export const markConversationRead = (conversationId, lastReadMessageId) => {
  return api.post(`/chat/conversations/${conversationId}/read`, { lastReadMessageId });
};

export const markMessageDelivered = (conversationId, messageId) => {
  return api.post(`/chat/conversations/${conversationId}/delivered`, { messageId });
};

export const setTyping = (conversationId, isTyping) => {
  return api.post(`/chat/conversations/${conversationId}/typing`, { isTyping });
};

export const setPinnedMessage = (conversationId, messageId, pinned = true) => {
  return api.put(`/chat/conversations/${conversationId}/pinned-message`, { messageId, pinned });
};

export const getReminders = (conversationId) => api.get(`/chat/conversations/${conversationId}/reminders`);

export const createReminder = (conversationId, payload) => api.post(`/chat/conversations/${conversationId}/reminders`, payload);

export const cancelReminder = (reminderId) => api.delete(`/chat/reminders/${reminderId}`);

export const editMessage = (messageId, content, version) => {
  return api.patch(`/chat/messages/${messageId}`, {
    content,
    ...(version ? { version } : {}),
  });
};

export const getMessageEditHistory = (messageId) => {
  return api.get(`/chat/messages/${messageId}/edit-history`);
};

export const deleteMessageForMe = (messageId) => {
  return api.delete(`/chat/messages/${messageId}`);
};

export const recallMessage = (messageId) => {
  return api.post(`/chat/messages/${messageId}/recall`);
};

export const addReaction = (messageId, emoji) => {
  return api.put(`/chat/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`);
};

export const removeReaction = (messageId, emoji) => {
  return api.delete(`/chat/messages/${messageId}/reactions/${encodeURIComponent(emoji)}`);
};

export const createPoll = (conversationId, payload) => {
  return api.post(`/chat/conversations/${conversationId}/polls`, payload);
};

export const votePoll = (messageId, payload) => {
  return api.post(`/chat/messages/${messageId}/poll/votes`, payload);
};

export const closePoll = (messageId) => {
  return api.post(`/chat/messages/${messageId}/poll/close`);
};

export const uploadFiles = (files) => {
  const formData = new FormData();
  Array.from(files).forEach((item) => {
    const file = item?.file || item;
    const relativePath = item?.relativePath || file.webkitRelativePath || file.name;
    formData.append("files", file);
    formData.append("relativePaths", relativePath);
  });
  return api.post("/chat/uploads", formData);
};

export const getProfile = () => {
  return api.get("/profile");
};

export const updateProfile = (fullname) => {
  return api.put("/profile", { fullname });
};

export const changePassword = (currentPassword, newPassword) => {
  return api.put("/profile/password", { currentPassword, newPassword });
};

export const uploadAvatar = (file) => {
  const formData = new FormData();
  formData.append("avatar", file);
  return api.post("/profile/avatar", formData);
};

export const issueRealtimeTicket = (reconnect = false) => {
  return api.post("/chat/realtime/ticket", { reconnect });
};

export const getRealtimeUrl = (ticket, reconnect = false) => {
  const origin = window.location?.origin || "http://localhost";
  const apiBase = /^https?:\/\//i.test(API_URL)
    ? API_URL
    : new URL(API_URL, origin).toString();
  const url = new URL(`${apiBase.replace(/\/$/, "")}/chat/realtime`);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("ticket", ticket);
  if (reconnect) url.searchParams.set("reconnect", "1");
  return url.toString();
};

export const getICEConfiguration = () => api.get("/chat/calls/ice-config");

export const sendCallControlEvent = ({ type, conversationId, callId, mediaType = "audio", deviceId = getOrCreateDeviceId(), token = "" }) =>
  api.post("/chat/calls/events", { type, conversationId, callId, mediaType, deviceId, ...(token ? { token } : {}) });

export const getCallHistory = (limit = 50) => api.get("/chat/calls/history", { params: { limit } });

export const getCall = (callId) => api.get(`/chat/calls/${encodeURIComponent(callId)}`);

export default {
  searchUsers,
  searchChat,
  getContacts,
  addContact,
  updateContactNickname,
  registerDeviceToken,
  unregisterDeviceToken,
  getOrCreateDeviceId,
  getConversations,
  createDirectConversation,
  createGroupConversation,
  updateConversationSettings,
  updateConversationUserSettings,
  addConversationMembers,
  removeConversationMember,
  updateConversationMemberNickname,
  getMessages,
  getMessageCatchUp,
  searchConversationMessages,
  sendMessage,
  markConversationRead,
  markMessageDelivered,
  setTyping,
  setPinnedMessage,
  getReminders,
  createReminder,
  cancelReminder,
  editMessage,
  getMessageEditHistory,
  deleteMessageForMe,
  recallMessage,
  addReaction,
  removeReaction,
  createPoll,
  votePoll,
  closePoll,
  uploadFiles,
  getProfile,
  updateProfile,
  changePassword,
  uploadAvatar,
  getRealtimeUrl,
  issueRealtimeTicket,
  getICEConfiguration,
  sendCallControlEvent,
  getCallHistory,
  getCall,
};
