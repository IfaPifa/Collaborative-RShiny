# Stage 1: Build the Angular app with Node 22
FROM node:22 AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
RUN chmod +x node_modules/.bin/*
COPY . .
RUN npm run build --configuration=production

# Stage 2: Serve the app using Nginx
FROM nginx:stable-alpine
# This copies your 'dist' folder into the Nginx web folder
COPY --from=build /app/dist/*/browser /usr/share/nginx/html

# --- ADD THIS LINE ---
# This copies the routing fix into the Nginx container
COPY angular-nginx.conf /etc/nginx/conf.d/default.conf
# ---------------------

# Standard web port (Docker Compose will map this to 4200 later)
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]