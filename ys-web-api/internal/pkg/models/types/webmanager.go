package types

type WebManager struct {
	ID         int    `json:"id" gorm:"primaryKey"`
	Name       string `json:"name"`
	Server     string `json:"server"`
	ServerLink string `json:"serverlink" gorm:"column:serverlink"`
	FePort     string `json:"feport" gorm:"column:feport"`
	BePort     string `json:"beport" gorm:"column:beport"`
	Path       string `json:"path" gorm:"column:path"`
	Image      string `json:"image" gorm:"column:image"`
	Userid     int    `json:"userid" gorm:"column:userid"`
	Userdate   string `json:"userdate" gorm:"column:userdate"`
	Categories []int  `json:"categories" gorm:"-"`
}

func (WebManager) TableName() string {
	return "webmanager" // 👈 Đây là tên bảng đúng trong MySQL
}

type Categories struct {
	ID   int    `json:"idcategory"`
	Name string `json:"namecategory"`
}