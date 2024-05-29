#!/bin/bash

# Set up variables
echo "Enter the domain name for your Nextcloud instance:"
read DOMAIN

echo "Enter the administrator username for your Nextcloud instance:"
read ADMIN_USER

echo "Enter the administrator password for your Nextcloud instance:"
read ADMIN_PASS

echo "Enter the database username for your Nextcloud instance:"
read DB_USER

echo "Enter the database password for your Nextcloud instance:"
read DB_PASS

echo "Enter the name of the database for your Nextcloud instance:"
read DB_NAME

echo "Enter the location for your Nextcloud data directory. The data directory will be added to the path (e.g., /nextcloud/drive/nc/):"
read DATADIR

IP_ADDRESS=$(hostname -I | awk '{print $1}')


# Update package lists and upgrade packages
sudo apt update -y
sudo apt upgrade -y
sudo apt-get install -y curl
sudo apt-get install -y bzip2
sudo apt-get install -y apt-utils
sudo apt-get install -y cron
sudo apt-get install -y libmagickcore-6.q16-6-extra


# Install nginx
sudo apt -y install nginx


# Install PHP and required extensions
sudo apt install -y apt-transport-https lsb-release ca-certificates wget
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo apt update
sudo apt -y install php8.1-{bcmath,fpm,xml,mysql,zip,intl,ldap,gd,cli,bz2,curl,mbstring,opcache,soap,redis,apcu,gmp,imagick}

# Install MariaDB
sudo apt -y install mariadb-server

# Configure MariaDB
sudo mysql_secure_installation <<EOF
n
n
y
y
y
y
y
EOF

# Create Nextcloud database and user
mysql -e "CREATE DATABASE $DB_NAME; GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; FLUSH PRIVILEGES;"

# Set up nginx configuration
sudo tee /etc/nginx/conf.d/nextcloud.conf > /dev/null <<EOL
upstream php-handler {
    server 127.0.0.1:9000;
    server unix:/var/run/php/php8.1-fpm.sock;
}

map \$arg_v \$asset_immutable {
    "" "";
    default "immutable";
}

server {
    listen 80;
    #listen [::]:80;
    server_name ${DOMAIN} ${IP_ADDRESS};

    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;


#server {
   #listen 443      ssl http2;
   #listen [::]:443 ssl http2;
   #server_name ${DOMAIN} ${IP_ADDRESS};

    # Path to the root of your installation
    root /opt/nextcloud;

    #ssl_certificate     /etc/ssl/nginx/${DOMAIN}.crt;
    #ssl_certificate_key /etc/ssl/nginx/${DOMAIN}.key;

    server_tokens off;

    client_max_body_size 512M;
    client_body_timeout 600s;
    fastcgi_buffers 64 4K;

    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+js>

    client_body_buffer_size 512k;

    add_header Referrer-Policy                   "no-referrer"       always;
    add_header X-Content-Type-Options            "nosniff"           always;
    add_header X-Download-Options                "noopen"            always;
    add_header X-Frame-Options                   "SAMEORIGIN"        always;
    add_header X-Permitted-Cross-Domain-Policies "none"              always;
    add_header X-Robots-Tag                      "noindex, nofollow" always;
    add_header X-XSS-Protection                  "1; mode=block"     always;
    real_ip_header    X-Real-IP;
    set_real_ip_from ${IP_ADDRESS};
    fastcgi_hide_header X-Powered-By;

    index index.php index.html /index.php\$request_uri;

    location = / {
        if ( \$http_user_agent ~ ^DavClnt ) {
            return 302 /remote.php/webdav/\$is_args\$args;
        }
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ^~ /.well-known {
        location = /.well-known/carddav { return 301 /remote.php/dav/; }
        location = /.well-known/caldav  { return 301 /remote.php/dav/; }
        location = /.well-known/webfinder  { return 301 /index.php/.well-known/webfinger; }
        location = /.well-known/nodeinfo  { return 301 /index.php/.well-known/nodeinfo; }

        location /.well-known/acme-challenge    { try_files \$uri \$uri/ =404; }
        location /.well-known/pki-validation    { try_files \$uri \$uri/ =404; }
        return 301 /index.php\$request_uri;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/)  { return 404; }
    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

    location ~ \.php(?:\$|/) {
        # Required for legacy support
        rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+|.+\/richdocumentscode\/proxy) /index.php\$request_uri;

        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;

        try_files \$fastcgi_script_name =404;

        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;

        fastcgi_param modHeadersAvailable true;         
        fastcgi_param front_controller_active true;    
        fastcgi_pass php-handler;

        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;

        fastcgi_max_temp_file_size 0;
    }

    location ~ \.(?:css|js|svg|gif|png|jpg|ico|wasm|tflite|map)\$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control "public, max-age=15778463, \$asset_immutable";
        access_log off;     

        location ~ \.wasm\$ {
            default_type application/wasm;
        }
    }

    location ~ \.woff2?\$ {
        try_files \$uri /index.php\$request_uri;
        expires 7d;         
        access_log off;    
    }

    location /remote {
        return 301 /remote.php\$request_uri;
    }

    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
}
EOL


# Restart nginx
sudo systemctl restart nginx


# Install Nextcloud
sudo mkdir -p /opt/nextcloud
sudo wget https://download.nextcloud.com/server/releases/latest.tar.bz2 -O /tmp/nextcloud-latest.tar.bz2
sudo tar -xjf /tmp/nextcloud-latest.tar.bz2 -C /opt/nextcloud --strip-components=1
sudo chown -R www-data:www-data /opt/nextcloud

# Automate initial setup
sudo -u www-data php /opt/nextcloud/occ maintenance:install \
    --database=mysql \
    --database-name="$DB_NAME" \
    --database-user="$DB_USER" \
    --database-pass="$DB_PASS" \
    --admin-user="$ADMIN_USER" \
    --admin-pass="$ADMIN_PASS"




# Set trusted domain 1 to $DOMAIN
sudo -u www-data php /opt/nextcloud/occ config:system:set trusted_domains 1 --value="$DOMAIN"

# Set trusted domain 2 to $IP_ADDRESS
sudo -u www-data php /opt/nextcloud/occ config:system:set trusted_domains 2 --value="$IP_ADDRESS"

# Set maintenance window start to 1
sudo -u www-data php /opt/nextcloud/occ config:system:set maintenance_window_start --value="1"

# Set default phone region to DE (Germany)
sudo -u www-data php /opt/nextcloud/occ config:system:set default_phone_region --value="DE"

# Set bulkupload.enabled to false as a boolean
sudo -u www-data php /opt/nextcloud/occ config:system:set bulkupload.enabled --value=false --type=boolean

# Set PHP memory limit to 512M
sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.1/fpm/php.ini

# Add support for MIME type application/javascript in Nginx
sudo sed -i 's|application/javascript                js;|application/javascript                js mjs;|' /etc/nginx/mime.types

# Update overwrite.cli.url in Nextcloud config to use https://${DOMAIN}
sudo sed -i "s/'overwrite.cli.url' => 'http:\/\/localhost'/\'overwrite.cli.url' => 'https:\/\/${DOMAIN}'/" /opt/nextcloud/config/config.php

# Set PHP output_buffering to 0
sudo sed -i 's/^output_buffering =.*/output_buffering = 0/' /etc/php/8.1/fpm/php.ini

# Set PHP upload_max_filesize to 1000M
sudo sed -i 's/^upload_max_filesize =.*/upload_max_filesize = 1000M/' /etc/php/8.1/fpm/php.ini

# Set PHP post_max_size to 1000M
sudo sed -i 's/^post_max_size =.*/post_max_size = 1000M/' /etc/php/8.1/fpm/php.ini

# Uncomment clear_env = no in www.conf
sudo sed -i 's/;clear_env = no/clear_env = no/' /etc/php/8.1/fpm/pool.d/www.conf

# Move existing data directory
sudo mkdir -p "$DATADIR"
sudo mv -v /opt/nextcloud/data "$DATADIR"
sudo chown -R www-data:www-data "$DATADIR/data"

# Modify Nextcloud configuration
sudo cp -p /opt/nextcloud/config/config.php /opt/nextcloud/config/config.php.bk
sudo sed -i "s|'datadirectory' => '/opt/nextcloud/data',|'datadirectory' => '$DATADIR/data',|" /opt/nextcloud/config/config.php


#Redis
apt install -y redis php8.1-redis php8.1-apcu
sudo usermod -aG redis www-data
# Uncomment the line defining the unixsocket in redis.conf
sudo sed -i '/^# unixsocket \/var\/run\/redis\/redis-server\.sock/s/^# //' /etc/redis/redis.conf

# Uncomment the line defining the unixsocketperm in redis.conf
sudo sed -i '/^# unixsocketperm 700/s/^# //' /etc/redis/redis.conf

# Change the value of unixsocketperm from 700 to 770 in redis.conf
sudo sed -i 's/^unixsocketperm 700/unixsocketperm 770/' /etc/redis/redis.conf


# Append 'apc.enable_cli=1' to the end of /etc/php/8.1/cli/php.ini
sudo sed -i '$ a\apc.enable_cli=1' /etc/php/8.1/cli/php.ini


sudo sed -i "/);/i \\
  'filelocking.enabled' => true,\\
  'memcache.local' => '\\\\\\\\OC\\\\\\\\Memcache\\\\\\\\APCu',\\
  'memcache.locking' => '\\\\\\\\OC\\\\\\\\Memcache\\\\\\\\Redis',\\
  'memcache.distributed' => '\\\\\\\\OC\\\\\\\\Memcache\\\\\\\\Redis',\\
  'redis' => array (\\
    'host' => '/var/run/redis/redis-server.sock',\\
    'port' => 0,\\
    'timeout' => 0.0,\\
  )," /opt/nextcloud/config/config.php



# Add the cron job
(crontab -l 2>/dev/null; echo "*/5 * * * * sudo -u www-data php /opt/nextcloud/cron.php") | crontab -

sudo truncate -s 0 /var/log/nginx/error.log
sudo truncate -s 0 /"$DATADIR/data/nextcloud.log"

# Display message with URL to access Nextcloud instance
echo "Nextcloud has been installed successfully. You can access it at https://${DOMAIN} after the VM restarted."
sleep 10

reboot
