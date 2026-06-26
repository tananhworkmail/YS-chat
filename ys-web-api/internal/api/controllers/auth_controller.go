package controllers

import (
	"net/http"
	"time"

	"web-api/internal/pkg/models/request"
	// "web-api/internal/pkg/models/types" // Import nếu cần dùng cho token
	"web-api/internal/api/services" // Đảm bảo import đúng service của bạn

	"github.com/dgrijalva/jwt-go"
	"github.com/gin-gonic/gin"
)

var jwtSecret = []byte("TYTHAC@123")

// Đổi tên thành AuthController để bao quát cả Đăng nhập, Đăng ký và Quên mật khẩu
type AuthController struct {
	BaseController
}

var Auth = &AuthController{}

// ---------------------------------------------------------
// 1. ĐĂNG NHẬP
// ---------------------------------------------------------
func (h *AuthController) Login(c *gin.Context) {
	var requestParams request.LoginRequest
	if err := c.ShouldBindJSON(&requestParams); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "INVALID_INPUT"}) // Trả mã lỗi cứng nếu bind thất bại
		return
	}

	loginRes, err := services.AuthServiceInstance.Login(requestParams.Userid, requestParams.Password)
	if err != nil {
		// Trả về Mã lỗi lấy từ Service (ví dụ: INVALID_CREDENTIALS)
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	token, _ := generateToken(loginRes.Userid, loginRes.Fullname)
	
	c.JSON(http.StatusOK, gin.H{
		"token":      token,
		"account_id": loginRes.AccountID,
		"userid":     loginRes.Userid,
		"fullname":   loginRes.Fullname,
	})
}

// ---------------------------------------------------------
// 2. ĐĂNG KÝ
// ---------------------------------------------------------
func (h *AuthController) Register(c *gin.Context) {
	var requestParams request.RegisterRequest
	if err := c.ShouldBindJSON(&requestParams); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Dữ liệu đăng ký không hợp lệ."})
		return
	}

	err := services.AuthServiceInstance.Register(requestParams)
	if err != nil {
		// Trả về lỗi từ Service (VD: "5 số cuối CMND không khớp")
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Đăng ký tài khoản thành công"})
}

// ---------------------------------------------------------
// 3. QUÊN MẬT KHẨU
// ---------------------------------------------------------
func (h *AuthController) ForgotPassword(c *gin.Context) {
	var requestParams request.ForgotRequest
	if err := c.ShouldBindJSON(&requestParams); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Dữ liệu xác minh không hợp lệ."})
		return
	}

	// Giả sử bạn cấp mật khẩu mặc định mới là "123456" khi reset thành công
	newPassword := "123456"
	err := services.AuthServiceInstance.ResetPassword(requestParams, newPassword)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Mật khẩu của bạn đã được đặt lại thành: 123456"})
}

// ---------------------------------------------------------
// HÀM TẠO TOKEN
// ---------------------------------------------------------
func generateToken(userid string, fullname string) (string, error) {
	claims := jwt.MapClaims{
		"exp":      time.Now().Add(time.Hour * 72).Unix(),
		"userid":   userid,
		"fullname": fullname,
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	tokenString, err := token.SignedString(jwtSecret)
	if err != nil {
		return "", err
	}

	return tokenString, nil
}