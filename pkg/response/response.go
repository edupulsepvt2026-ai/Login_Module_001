package response

import "github.com/gin-gonic/gin"

type Response struct {
	Success bool        `json:"success"`
	Code    string      `json:"code,omitempty"`
	Message string      `json:"message,omitempty"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

func OK(c *gin.Context, data interface{}) {
	c.JSON(200, Response{Success: true, Data: data})
}

func Created(c *gin.Context, data interface{}) {
	c.JSON(201, Response{Success: true, Data: data})
}

func ErrorResponse(c *gin.Context, status int, code, err string) {
	c.JSON(status, Response{Success: false, Code: code, Error: err})
}

func BadRequest(c *gin.Context, err string) {
	ErrorResponse(c, 400, "bad_request", err)
}

func BadRequestWithCode(c *gin.Context, code, err string) {
	ErrorResponse(c, 400, code, err)
}

func Unauthorized(c *gin.Context, err string) {
	ErrorResponse(c, 401, "unauthorized", err)
}

func UnauthorizedWithCode(c *gin.Context, code, err string) {
	ErrorResponse(c, 401, code, err)
}

func Forbidden(c *gin.Context, err string) {
	ErrorResponse(c, 403, "forbidden", err)
}

func InternalError(c *gin.Context, err string) {
	ErrorResponse(c, 500, "internal_error", err)
}

func InternalErrorWithCode(c *gin.Context, code, err string) {
	ErrorResponse(c, 500, code, err)
}
