import axios from "axios";
const API_URL = import.meta.env.VITE_API_URL || "/api/v1";

const api = axios.create({
  baseURL: API_URL,
  timeout: 15000,
});

export const loginByAccount = (params) => api.post("/auth/login", {
  userid: params.userid,
  password: params.password,
});

export const register = (params) => api.post("/auth/register", {
  userid: params.userid,
  fullname: params.fullname,
  password: params.password,
  idCardSuffix: params.idCardSuffix,
});

export const forgotPassword = (params) => api.post("/auth/forgot-password", {
  userid: params.userid,
  fullname: params.fullname,
  birthday: params.birthday,
  idCard: params.idCard,
});

// Đảm bảo object này có đủ 3 hàm
export default {
  loginByAccount,
  register,
  forgotPassword,
};
