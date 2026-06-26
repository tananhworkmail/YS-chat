package services

import (
	"errors"
	"math"

	"web-api/internal/pkg/database"
	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/response"

	"gorm.io/gorm"
)

type BaseService struct{}

func (s *BaseService) Create(value interface{}) error {
	return database.GetDB().Create(value).Error
}

func (s *BaseService) Save(value interface{}) error {
	return database.GetDB().Save(value).Error
}

func (s *BaseService) Updates(where interface{}, value interface{}) error {
	return database.GetDB().Model(where).Updates(value).Error
}

func (s *BaseService) DeleteByModel(model interface{}) (count int64, err error) {
	db := database.GetDB().Delete(model)
	err = db.Error
	if err != nil {
		return
	}
	count = db.RowsAffected
	return
}

func (s *BaseService) DeleteByWhere(model, where interface{}) (count int64, err error) {
	db := database.GetDB().Where(where).Delete(model)
	err = db.Error
	if err != nil {
		return
	}
	count = db.RowsAffected
	return
}

func (s *BaseService) DeleteByID(model interface{}, id uint64) (count int64, err error) {
	db := database.GetDB().Where("id=?", id).Delete(model)
	err = db.Error
	if err != nil {
		return
	}
	count = db.RowsAffected
	return
}

func (s *BaseService) DeleteByIDS(model interface{}, ids []uint64) (count int64, err error) {
	db := database.GetDB().Where("id in (?)", ids).Delete(model)
	err = db.Error
	if err != nil {
		return
	}
	count = db.RowsAffected
	return
}

func (s *BaseService) FirstById(out interface{}, id uint64) (notFound bool, err error) {
	err = database.GetDB().First(out, id).Error
	if err != nil {
		notFound = errors.Is(err, gorm.ErrRecordNotFound)
	}
	return
}

func (s *BaseService) First(where interface{}, out interface{}, associations []string) (notFound bool, err error) {
	db := database.GetDB()
	for _, a := range associations {
		db = db.Preload(a)
	}

	err = db.Where(where).First(out).Error
	if err != nil {
		notFound = errors.Is(err, gorm.ErrRecordNotFound)
	}
	return
}

func (s *BaseService) Find(where interface{}, out interface{}, associations []string, orders ...string) (err error) {
	db := database.GetDB()
	for _, a := range associations {
		db = db.Preload(a)
	}

	db = db.Where(where)
	if len(orders) > 0 {
		for _, order := range orders {
			db = db.Order(order)
		}
	}
	return db.Find(out).Error
}

func (s *BaseService) Scan(model, where interface{}, out interface{}) (notFound bool, err error) {
	err = database.GetDB().Model(model).Where(where).Scan(out).Error
	if err != nil {
		notFound = errors.Is(err, gorm.ErrRecordNotFound)
	}
	return
}

func (s *BaseService) ScanList(model, where interface{}, out interface{}, orders ...string) error {
	db := database.GetDB().Model(model).Where(where)
	if len(orders) > 0 {
		for _, order := range orders {
			db = db.Order(order)
		}
	}
	return db.Scan(out).Error
}

func (s *BaseService) Pagination(model, out interface{}, pageInfo request.PageInfo, associations []string) (response.PaginationResponse, error) {
	db := database.GetDB()
	page := response.PaginationResponse{
		PageNumber: pageInfo.PageNumber,
	}
	offset := (pageInfo.PageNumber - 1) * pageInfo.PageSize

	// 查詢總數量
	if err := db.Model(model).Count(&page.TotalRow).Error; err != nil {
		return page, err
	}

	// 預先加載
	for _, a := range associations {
		db = db.Preload(a)
	}

	// 計算總頁數
	if page.TotalRow > int64(pageInfo.PageSize) {
		page.TotalPage = int(math.Ceil(float64(page.TotalRow) / float64(pageInfo.PageSize)))
	} else {
		page.TotalPage = 1
	}

	// 數據資料
	if err := db.Limit(pageInfo.PageSize).Offset(offset).Find(out).Error; err != nil {
		return page, err
	}

	page.List = out
	return page, nil
}
