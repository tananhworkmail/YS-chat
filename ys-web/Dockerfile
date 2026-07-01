# Sử dụng Node để build Vue
FROM node:18-alpine AS build
WORKDIR /app

# Copy package.json trước để cache dependency
COPY package.json package-lock.json ./ 
RUN npm install

# Copy toàn bộ source code
COPY . .

# Kiểm tra xem file logo.png có tồn tại không
RUN ls -l src/assets/

# Build dự án
RUN npm run build

# Dùng Nginx để chạy Vue
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html

# Cấu hình Nginx cho Vue Router (SPA)
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 1800
CMD ["nginx", "-g", "daemon off;"]
