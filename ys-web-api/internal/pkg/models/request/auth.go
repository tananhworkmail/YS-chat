package request

// RegisterRequest nhận dữ liệu khi người dùng đăng ký mới
type RegisterRequest struct {
	Userid       string `json:"userid" binding:"required"`
	Fullname     string `json:"fullname" binding:"required"`
	Password     string `json:"password" binding:"required"`
	IdCardSuffix string `json:"idCardSuffix" binding:"required,len=5"`
}

// ForgotRequest nhận dữ liệu xác minh khi bấm Quên mật khẩu
type ForgotRequest struct {
	Userid   string `json:"userid" binding:"required"`
	Fullname string `json:"fullname" binding:"required"`
	Birthday string `json:"birthday" binding:"required"` // Định dạng: YYYY-MM-DD
	IdCard   string `json:"idCard" binding:"required"`
}

// LoginRequest nhận dữ liệu khi người dùng đăng nhập
type LoginRequest struct {
	Userid   string `json:"userid" binding:"required"`
	Password string `json:"password" binding:"required"`
}