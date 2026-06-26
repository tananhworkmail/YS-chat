package types

// LoginResponse định nghĩa cấu trúc dữ liệu trả về khi đăng nhập thành công
type LoginResponse struct {
	AccountID int    `json:"account_id"`
	Userid    string `json:"userid"`
	Fullname  string `json:"fullname"`
	Avatar    string `json:"avatar"`
	Token     string `json:"token,omitempty"`
}

// HRMEmployee map cấu trúc các cột của bảng ST_NHANVIEN từ SQL Server 2008 R2
type HRMEmployee struct {
	NV_MA       string `gorm:"column:NV_MA"`
	NV_Ten      string `gorm:"column:NV_Ten"`
	NV_Ngaysinh string `gorm:"column:NV_Ngaysinh"` // Định dạng chuỗi YYYY-MM-DD sau khi convert ở SQL
	NV_CMND     string `gorm:"column:NV_CMND"`
	NV_THOIVIEC bool   `gorm:"column:NV_THOIVIEC"`
}