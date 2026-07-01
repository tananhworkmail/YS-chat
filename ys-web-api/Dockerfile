# ========== STAGE 1: BUILD ==========
FROM golang:1.22-alpine AS build_base

# Thiết lập môi trường build
ENV CGO_ENABLED=0 \
    GO111MODULE=on \
    TZ=Asia/Ho_Chi_Minh

# Cài đặt các gói cần thiết
RUN apk add --no-cache git tzdata ca-certificates

# Đặt thư mục làm việc
WORKDIR /src

# Copy go.mod và go.sum trước để cache dependency
COPY go.mod go.sum ./
RUN go mod download

# Copy toàn bộ mã nguồn
COPY . .

# Build binary
RUN go build -o /out/webapi ./cmd/main.go


# ========== STAGE 2: RUN ==========
FROM alpine:3.19

# Cài đặt chứng chỉ SSL và timezone
RUN apk add --no-cache ca-certificates tzdata \
    && update-ca-certificates

# Đặt timezone VN
ENV TZ=Asia/Ho_Chi_Minh
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Đặt thư mục làm việc
WORKDIR /app

# Copy file binary từ stage trước
COPY --from=build_base /out/webapi /app/webapi

# Copy thêm các thư mục cần thiết (nếu có)
COPY --from=build_base /src/data /app/data
COPY --from=build_base /src/log /app/log

# Phân quyền thực thi
RUN chmod +x /app/webapi

# Mở cổng 3666
EXPOSE 3666

# Chạy ứng dụng
CMD ["/app/webapi"]
