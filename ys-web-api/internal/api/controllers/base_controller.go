package controllers

import "github.com/gin-gonic/gin"

type BaseController struct{}

func (c *BaseController) ValidateReqParams(ctx *gin.Context, requestParams interface{}) error {
	var err error

	switch ctx.ContentType() {
	case "application/json":
		err = ctx.ShouldBindJSON(requestParams)
	case "application/xml":
		err = ctx.ShouldBindXML(requestParams)
	case "":
		err = ctx.ShouldBindUri(requestParams)
		err = ctx.ShouldBindQuery(requestParams)
	default:
		err = ctx.ShouldBind(requestParams)
	}

	if err != nil {
		return err
	}

	return nil
}
