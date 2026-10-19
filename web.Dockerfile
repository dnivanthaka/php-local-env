FROM nginx:alpine

# Remove any default configurations that might clash
RUN rm -f /etc/nginx/conf.d/default.conf

# Copy our clean configuration straight into the container
COPY ./docker/nginx/default.conf /etc/nginx/conf.d/default.conf
