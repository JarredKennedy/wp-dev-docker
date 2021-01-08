FROM wordpress:latest

ENV WORDPRESS_DEBUG=1
ENV WORDPRESS_CONFIG_EXTRA="define(\"WP_DEBUG_LOG\", true); \
    define(\"SCRIPT_DEBUG\", true);"

RUN echo "file_uploads = On\n" \
         "memory_limit = 500M\n" \
         "upload_max_filesize = 500M\n" \
         "post_max_size = 500M\n" \
         "max_execution_time = 600\n" \
         > /usr/local/etc/php/conf.d/wordpress.ini
