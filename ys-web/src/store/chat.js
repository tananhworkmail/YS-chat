import axios from "axios";

const API_URL = import.meta.env.VITE_API_URL || "/api/v1";

const api = axios.create({
  baseURL: API_URL,
});

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

export const getContacts = () => {
  return api.get("/chat/contacts");
};

export const addContact = (userid) => {
  return api.post("/chat/contacts", { userid });
};

export const registerDeviceToken = (token, platform) => {
  return api.post("/chat/devices", { token, platform });
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

export const addConversationMembers = (conversationId, userids) => {
  return api.post(`/chat/conversations/${conversationId}/members`, { userids });
};

export const removeConversationMember = (conversationId, userid) => {
  return api.delete(`/chat/conversations/${conversationId}/members/${encodeURIComponent(userid)}`);
};

export const updateConversationMemberNickname = (conversationId, userid, nickname) => {
  return api.put(`/chat/conversations/${conversationId}/members/${encodeURIComponent(userid)}/nickname`, { nickname });
};

export const getMessages = (conversationId) => {
  return api.get(`/chat/conversations/${conversationId}/messages`);
};

export const sendMessage = (conversationId, payload) => {
  return api.post(`/chat/conversations/${conversationId}/messages`, payload);
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

export const getRealtimeUrl = () => {
  const token = localStorage.getItem("user_token") || "";
  const origin = window.location?.origin || "http://localhost";
  const apiBase = /^https?:\/\//i.test(API_URL)
    ? API_URL
    : new URL(API_URL, origin).toString();
  const url = new URL(`${apiBase.replace(/\/$/, "")}/chat/realtime`);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("token", token);
  return url.toString();
};

export default {
  searchUsers,
  getContacts,
  addContact,
  registerDeviceToken,
  getConversations,
  createDirectConversation,
  createGroupConversation,
  updateConversationSettings,
  addConversationMembers,
  removeConversationMember,
  updateConversationMemberNickname,
  getMessages,
  sendMessage,
  uploadFiles,
  getProfile,
  updateProfile,
  changePassword,
  uploadAvatar,
  getRealtimeUrl,
};
