package controllers

import (
	"web-api/internal/pkg/models/response"

	"github.com/gin-gonic/gin"
)

type CommonController struct {
	*BaseController
}

var Common = &CommonController{}

func (c *CommonController) Ping(ctx *gin.Context) {
	response.Ok(ctx)
}
