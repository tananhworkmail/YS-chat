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

type ProfileService struct {
	*BaseService
}

var ProfileServiceInstance = &ProfileService{}

func (s *ProfileService) GetProfile(userid string) (*types.ChatUser, error) {
	db, err := database.WEBDB_DBConnection()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	var user types.ChatUser
	err = db.Table("users").
		Select("userid, fullname, COALESCE(avatar, '') AS avatar").
		Where("userid = ?", userid).
		Scan(&user).Error
	if err != nil || user.Userid == "" {
		return nil, errors.New(ErrUserNotRegistered)
	}

	return &user, nil
}

func (s *ProfileService) UpdateProfile(userid string, req request.UpdateProfileRequest) (*types.ChatUser, error) {
	db, err := database.WEBDB_DBConnection()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	fullname := strings.TrimSpace(req.Fullname)
	if fullname == "" {
		return nil, errors.New(ErrInvalidInput)
	}

	err = db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Table("users").Where("userid = ?", userid).Update("fullname", fullname).Error; err != nil {
			return err
		}
		return tx.Table("accounts").Where("userid = ?", userid).Update("fullname", fullname).Error
	})
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	return s.GetProfile(userid)
}

func (s *ProfileService) ChangePassword(userid string, req request.ChangePasswordRequest) error {
	db, err := database.WEBDB_DBConnection()
	if err != nil {
		return errors.New(ErrSystem)
	}

	if strings.TrimSpace(req.NewPassword) == "" || len(req.NewPassword) < 6 {
		return errors.New(ErrInvalidInput)
	}

	var account struct {
		ID       int
		Password string
	}
	err = db.Table("accounts").Select("id, password").Where("userid = ?", userid).Scan(&account).Error
	if err != nil || account.ID == 0 {
		return errors.New(ErrUserNotRegistered)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(account.Password), []byte(req.CurrentPassword)); err != nil {
		return errors.New(ErrInvalidCredentials)
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return errors.New(ErrSystem)
	}

	if err := db.Table("accounts").Where("id = ?", account.ID).Update("password", string(hashedPassword)).Error; err != nil {
		return errors.New(ErrSystem)
	}

	return nil
}

func (s *ProfileService) UpdateAvatar(userid string, avatarURL string) (*types.ChatUser, error) {
	db, err := database.WEBDB_DBConnection()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	if strings.TrimSpace(avatarURL) == "" {
		return nil, errors.New(ErrInvalidInput)
	}

	if err := db.Table("users").Where("userid = ?", userid).Update("avatar", avatarURL).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}

	return s.GetProfile(userid)
}
