package controllers

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"web-api/internal/api/services"
	"web-api/internal/pkg/models/request"

	"github.com/gin-gonic/gin"
)

type ProfileController struct {
	BaseController
}

var Profile = &ProfileController{}

func (h *ProfileController) Me(c *gin.Context) {
	user, err := services.ProfileServiceInstance.GetProfile(currentUserid(c))
	if err != nil {
		writeProfileError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"user": user})
}

func (h *ProfileController) UpdateProfile(c *gin.Context) {
	var req request.UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	user, err := services.ProfileServiceInstance.UpdateProfile(currentUserid(c), req)
	if err != nil {
		writeProfileError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"user": user})
}

func (h *ProfileController) ChangePassword(c *gin.Context) {
	var req request.ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	if err := services.ProfileServiceInstance.ChangePassword(currentUserid(c), req); err != nil {
		writeProfileError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "PASSWORD_UPDATED"})
}

func (h *ProfileController) UploadAvatar(c *gin.Context) {
	file, err := c.FormFile("avatar")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	if !strings.HasPrefix(file.Header.Get("Content-Type"), "image/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	uploadDir := filepath.Join("uploads", "avatars")
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": services.ErrSystem})
		return
	}

	filename := fmt.Sprintf("%s_%d_%s", currentUserid(c), time.Now().UnixNano(), profileSafeFilename(file.Filename))
	destination := filepath.Join(uploadDir, filename)
	if err := c.SaveUploadedFile(file, destination); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": services.ErrSystem})
		return
	}

	user, err := services.ProfileServiceInstance.UpdateAvatar(currentUserid(c), "/"+filepath.ToSlash(destination))
	if err != nil {
		writeProfileError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"user": user})
}

func writeProfileError(c *gin.Context, err error) {
	status := http.StatusBadRequest
	switch err.Error() {
	case services.ErrSystem:
		status = http.StatusInternalServerError
	case services.ErrUserNotRegistered:
		status = http.StatusNotFound
	case services.ErrInvalidCredentials:
		status = http.StatusUnauthorized
	}
	c.JSON(status, gin.H{"error": err.Error()})
}

func profileSafeFilename(filename string) string {
	filename = filepath.Base(strings.TrimSpace(filename))
	if filename == "" || filename == "." || filename == string(filepath.Separator) {
		return "avatar"
	}

	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	return replacer.Replace(filename)
}
