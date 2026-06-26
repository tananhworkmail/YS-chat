package services

import (
	"errors"
	"strings"

	"web-api/internal/pkg/database"
	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// ĐỊNH NGHĨA CÁC MÃ LỖI CHUẨN (Dành cho i18n Frontend)
const (
	ErrSystem               = "SYSTEM_ERROR"
	ErrInvalidInput         = "INVALID_INPUT"
	ErrUserAlreadyExists    = "USER_ALREADY_EXISTS"
	ErrHRMUserNotFound      = "HRM_USER_NOT_FOUND"
	ErrEmployeeResigned     = "EMPLOYEE_RESIGNED"
	ErrIDCardMismatch       = "ID_CARD_MISMATCH"
	ErrBirthdayMismatch     = "BIRTHDAY_MISMATCH"
	ErrInvalidCredentials   = "INVALID_CREDENTIALS"
	ErrAccountLocked        = "ACCOUNT_LOCKED"
	ErrUserNotRegistered    = "USER_NOT_REGISTERED"
)

type AuthService struct {
	*BaseService
}

var AuthServiceInstance = &AuthService{}

// ======================= 1. ĐĂNG KÝ =======================
func (s *AuthService) Register(req request.RegisterRequest) error {
	webDB, err := database.WEBDB_DBConnection()
	if err != nil {
		return errors.New(ErrSystem)
	}

	hrmDB, err := database.HRM_Connection()
	if err != nil {
		return errors.New(ErrSystem)
	}

	var existingCount int64
	webDB.Table("accounts").Where("userid = ?", req.Userid).Count(&existingCount)
	if existingCount > 0 {
		return errors.New(ErrUserAlreadyExists)
	}

	var roleID int
	webDB.Table("roles").Select("id").Where("role_name = ?", "USER").Scan(&roleID)
	if roleID == 0 {
		return errors.New(ErrSystem)
	}

	var emp types.HRMEmployee
	queryHRM := `
		SELECT NV_MA, NV_Ten, CONVERT(VARCHAR(10), NV_Ngaysinh, 120) AS NV_Ngaysinh, NV_CMND, NV_THOIVIEC 
		FROM ST_NHANVIEN WHERE NV_MA = ?
	`
	err = hrmDB.Raw(queryHRM, req.Userid).Scan(&emp).Error
	if err != nil || emp.NV_MA == "" {
		return errors.New(ErrHRMUserNotFound)
	}

	if emp.NV_THOIVIEC { 
    return errors.New(ErrEmployeeResigned)
}

	emp.NV_CMND = strings.TrimSpace(emp.NV_CMND)
	if !strings.HasSuffix(emp.NV_CMND, req.IdCardSuffix) {
		return errors.New(ErrIDCardMismatch)
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return errors.New(ErrSystem)
	}

	err = webDB.Transaction(func(tx *gorm.DB) error {
		account := map[string]interface{}{
			"userid":   req.Userid,
			"fullname": req.Fullname,
			"password": string(hashedPassword),
			"status":   1,
			"role_id":  roleID,
		}
		if err := tx.Table("accounts").Create(&account).Error; err != nil { return err }

		var newAccount struct{ ID int }
		tx.Table("accounts").Select("id").Where("userid = ?", req.Userid).Scan(&newAccount)

		user := map[string]interface{}{
			"account_id": newAccount.ID,
			"userid":     req.Userid,
			"fullname":   req.Fullname,
		}
		if err := tx.Table("users").Create(&user).Error; err != nil { return err }
		return nil
	})

	if err != nil {
		return errors.New(ErrSystem)
	}

	return nil
}

// ======================= 2. ĐĂNG NHẬP =======================
func (s *AuthService) Login(userid, password string) (*types.LoginResponse, error) {
	webDB, err := database.WEBDB_DBConnection()
	if err != nil { return nil, errors.New(ErrSystem) }

	var account struct {
		ID       int
		Password string
		Status   int
	}
	err = webDB.Table("accounts").Select("id, password, status").Where("userid = ?", userid).Scan(&account).Error
	if err != nil || account.ID == 0 {
		return nil, errors.New(ErrInvalidCredentials)
	}

	if account.Status == 0 {
		return nil, errors.New(ErrAccountLocked)
	}

	err = bcrypt.CompareHashAndPassword([]byte(account.Password), []byte(password))
	if err != nil {
		return nil, errors.New(ErrInvalidCredentials)
	}

	var res types.LoginResponse
	err = webDB.Table("users").Select("account_id, userid, fullname, avatar").Where("account_id = ?", account.ID).Scan(&res).Error
	if err != nil { return nil, errors.New(ErrSystem) }

	return &res, nil
}

// ======================= 3. QUÊN MẬT KHẨU =======================
func (s *AuthService) ResetPassword(req request.ForgotRequest, newPassword string) error {
	webDB, err := database.WEBDB_DBConnection()
	if err != nil { return errors.New(ErrSystem) }

	hrmDB, err := database.HRM_Connection()
	if err != nil { return errors.New(ErrSystem) }

	var accountID int
	webDB.Table("accounts").Select("id").Where("userid = ?", req.Userid).Scan(&accountID)
	if accountID == 0 { return errors.New(ErrUserNotRegistered) }

	var emp types.HRMEmployee
	queryHRM := `SELECT NV_MA, NV_Ten, CONVERT(VARCHAR(10), NV_Ngaysinh, 120) AS NV_Ngaysinh, NV_CMND FROM ST_NHANVIEN WHERE NV_MA = ?`
	err = hrmDB.Raw(queryHRM, req.Userid).Scan(&emp).Error
	if err != nil || emp.NV_MA == "" { return errors.New(ErrHRMUserNotFound) }

	emp.NV_CMND = strings.TrimSpace(emp.NV_CMND)
	if emp.NV_CMND != req.IdCard { return errors.New(ErrIDCardMismatch) }
	if emp.NV_Ngaysinh != req.Birthday { return errors.New(ErrBirthdayMismatch) }

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil { return errors.New(ErrSystem) }

	err = webDB.Table("accounts").Where("id = ?", accountID).Update("password", string(hashedPassword)).Error
	if err != nil { return errors.New(ErrSystem) }

	return nil
}