import axios from "axios";
const API_URL = import.meta.env.VITE_API_URL || "/api/v1";

const api = axios.create({
  baseURL: API_URL,
  timeout: 15000,
});

export const loginByAccount = async (params) => {
  try {
    const res = await api.post("/auth/login", {
      userid: params.userid,
      password: params.password,
    });
    return res;
  } catch (error) {
    throw error;
  }
};

export const register = async (params) => {
  try {
    const res = await api.post("/auth/register", {
      userid: params.userid,
      fullname: params.fullname,
      password: params.password,
      idCardSuffix: params.idCardSuffix,
    });
    return res;
  } catch (error) {
    throw error;
  }
};

export const forgotPassword = async (params) => {
  try {
    const res = await api.post("/auth/forgot-password", {
      userid: params.userid,
      fullname: params.fullname,
      birthday: params.birthday,
      idCard: params.idCard,
    });
    return res;
  } catch (error) {
    throw error;
  }
};

// Đảm bảo object này có đủ 3 hàm
export default {
  loginByAccount,
  register,
  forgotPassword,
};
