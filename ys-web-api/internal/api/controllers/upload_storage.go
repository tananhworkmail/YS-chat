package controllers

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
)

const (
	uploadIDBytes      = 16
	uploadSaveAttempts = 5
)

func saveUploadedFileRandom(file *multipart.FileHeader, uploadDir string, displayName string, prefix string) (string, error) {
	for attempt := 0; attempt < uploadSaveAttempts; attempt++ {
		storedName, err := randomStoredFilename(displayName, prefix)
		if err != nil {
			return "", err
		}

		destination := filepath.Join(uploadDir, storedName)
		if err := saveUploadedFileExclusive(file, destination); err != nil {
			if os.IsExist(err) {
				continue
			}
			return "", err
		}
		return destination, nil
	}

	return "", fmt.Errorf("could not allocate unique upload filename after %d attempts", uploadSaveAttempts)
}

func randomStoredFilename(displayName string, prefix string) (string, error) {
	id, err := randomHex(uploadIDBytes)
	if err != nil {
		return "", err
	}

	name := id + safeUploadExtension(displayName)
	if safePrefix := safeUploadPrefix(prefix); safePrefix != "" {
		name = safePrefix + "_" + name
	}
	return name, nil
}

func randomHex(size int) (string, error) {
	buffer := make([]byte, size)
	if _, err := rand.Read(buffer); err != nil {
		return "", err
	}
	return hex.EncodeToString(buffer), nil
}

func safeUploadExtension(displayName string) string {
	ext := strings.ToLower(filepath.Ext(displayName))
	if ext == "." || len(ext) > 20 || strings.ContainsAny(ext, `/\:*?"<>|`) {
		return ""
	}
	return ext
}

func safeUploadPrefix(prefix string) string {
	prefix = strings.TrimSpace(filepath.Base(prefix))
	if prefix == "" || prefix == "." || prefix == string(filepath.Separator) {
		return ""
	}

	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	prefix = strings.Trim(replacer.Replace(prefix), "._- ")
	if len(prefix) > 64 {
		prefix = prefix[:64]
	}
	return prefix
}

func saveUploadedFileExclusive(file *multipart.FileHeader, destination string) error {
	source, err := file.Open()
	if err != nil {
		return err
	}
	defer source.Close()

	target, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		return err
	}

	if _, err := io.Copy(target, source); err != nil {
		target.Close()
		os.Remove(destination)
		return err
	}

	return target.Close()
}
