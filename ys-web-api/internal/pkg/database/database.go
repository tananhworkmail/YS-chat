package database

import (
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"web-api/internal/pkg/config"

	"gorm.io/driver/mysql"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/driver/sqlserver"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var (
	DB              *gorm.DB
	connectionMu    sync.Mutex
	connectionCache = map[string]*gorm.DB{}
)

type Database struct {
	*gorm.DB
}

func Setup() error {
	configuration := config.GetConfig()

	db, err := cachedConnection("default", *configuration)
	if err != nil {
		return err
	}

	DB = db
	migration()

	return nil
}

func cachedConnection(name string, configuration config.Configuration) (*gorm.DB, error) {
	connectionMu.Lock()
	defer connectionMu.Unlock()

	if db, ok := connectionCache[name]; ok {
		return db, nil
	}

	db, err := CreateDatabaseConnection(&configuration)
	if err != nil {
		return nil, err
	}

	connectionCache[name] = db
	return db, nil
}

func CreateDatabaseConnection(configuration *config.Configuration) (*gorm.DB, error) {
	driver := strings.ToLower(configuration.Database.Driver)
	dsn, err := buildDSN(driver, configuration)
	if err != nil {
		return nil, errors.New("failed to build DSN")
	}

	logmode := configuration.Database.Logmode
	loglevel := logger.Silent
	if logmode {
		loglevel = logger.Info
	}
	newDBLogger := logger.New(
		log.New(getWriter(), "\r\n", log.LstdFlags),
		logger.Config{
			SlowThreshold:             time.Second,
			LogLevel:                  loglevel,
			IgnoreRecordNotFoundError: true,
			Colorful:                  false,
		},
	)

	var db *gorm.DB
	switch driver {
	case "mysql":
		db, err = gorm.Open(mysql.Open(dsn), &gorm.Config{Logger: newDBLogger})
	case "postgres":
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: newDBLogger})
	case "sqlite":
		db, err = gorm.Open(sqlite.Open(dsn), &gorm.Config{Logger: newDBLogger})
	case "sqlserver":
		db, err = gorm.Open(sqlserver.Open(dsn), &gorm.Config{Logger: newDBLogger})
	default:
		return nil, fmt.Errorf("unsupported driver: %s", driver)
	}

	if err != nil {
		return nil, errors.New("failed to open database connection")
	}

	sqlDB, err := db.DB()
	if err == nil {
		sqlDB.SetMaxIdleConns(5)
		sqlDB.SetMaxOpenConns(30)
		sqlDB.SetConnMaxIdleTime(5 * time.Minute)
		sqlDB.SetConnMaxLifetime(30 * time.Minute)
	}

	return db, nil
}

func buildDSN(driver string, configuration *config.Configuration) (string, error) {
	switch driver {
	case "mysql":
		return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
			configuration.Database.Username,
			configuration.Database.Password,
			configuration.Database.Host,
			configuration.Database.Port,
			configuration.Database.Dbname), nil
	case "postgres":
		mode := "disable"
		if configuration.Database.Sslmode {
			mode = "require"
		}
		return fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
			configuration.Database.Host,
			configuration.Database.Username,
			configuration.Database.Password,
			configuration.Database.Dbname,
			configuration.Database.Port,
			mode), nil
	case "sqlite":
		return "./" + configuration.Database.Dbname + ".db", nil
	case "sqlserver":
		mode := "disable"
		if configuration.Database.Sslmode {
			mode = "true"
		}
		return fmt.Sprintf("sqlserver://%s:%s@%s:%s?database=%s&encrypt=%s&connection+timeout=5",
			configuration.Database.Username,
			configuration.Database.Password,
			configuration.Database.Host,
			configuration.Database.Port,
			configuration.Database.Dbname,
			mode), nil
	default:
		return "", fmt.Errorf("unsupported driver: %s", driver)
	}
}

func getWriter() io.Writer {
	if err := os.MkdirAll("log", 0755); err != nil {
		return os.Stdout
	}

	file, err := os.OpenFile("log/database.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		return os.Stdout
	}
	return file
}

func migration() {
	// TODO: add migration if needed
}

func GetDB() *gorm.DB {
	return DB
}

func LYS_ERP_Connection() (*gorm.DB, error) {
	configuration := *config.GetConfig()
	configuration.Database.Driver = "sqlserver"
	configuration.Database.Host = "192.168.71.7"
	configuration.Database.Username = "tyxuan"
	configuration.Database.Password = "jack"
	configuration.Database.Dbname = "LYS_ERP"
	configuration.Database.Port = "1433"
	return cachedConnection("lys_erp", configuration)
}

func HRM_Connection() (*gorm.DB, error) {
	configuration := *config.GetConfig()
	configuration.Database.Driver = "sqlserver"
	configuration.Database.Host = "192.168.71.5"
	configuration.Database.Username = "sa"
	configuration.Database.Password = "IT@Admin17"
	configuration.Database.Dbname = "P0104-TYTHAC"
	configuration.Database.Port = "1433"
	return cachedConnection("hrm", configuration)
}

func WEBDB_DBConnection() (*gorm.DB, error) {
	configuration := *config.GetConfig()
	configuration.Database.Driver = "mysql"
	configuration.Database.Host = "192.168.71.78"
	configuration.Database.Username = "weblocal"
	configuration.Database.Password = "jack"
	configuration.Database.Dbname = "ysweb"
	configuration.Database.Port = "3306"
	return cachedConnection("webdb", configuration)
}
