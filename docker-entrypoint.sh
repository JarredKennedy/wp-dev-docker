#!/bin/bash
set -euo pipefail

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
	if [ "$(id -u)" = '0' ]; then
		user="${APACHE_RUN_USER:-www-data}"
		group="${APACHE_RUN_GROUP:-www-data}"
	else
		user="$(id -u)"
		group="$(id -g)"
	fi

	if [ ! -e index.php ] && [ ! -e wp-includes/version.php ]; then
		wp core download --version="$WORDPRESS_VERSION" --allow-root

		if [ ! -e .htaccess ]; then
			cat > .htaccess <<-'EOF'
				# BEGIN WordPress
				<IfModule mod_rewrite.c>
				RewriteEngine On
				RewriteBase /
				RewriteRule ^index\.php$ - [L]
				RewriteCond %{REQUEST_FILENAME} !-f
				RewriteCond %{REQUEST_FILENAME} !-d
				RewriteRule . /index.php [L]
				</IfModule>
				# END WordPress
			EOF
			chown "$user:$group" .htaccess
		fi
	fi

	uniqueEnvs=(
		AUTH_KEY
		SECURE_AUTH_KEY
		LOGGED_IN_KEY
		NONCE_KEY
		AUTH_SALT
		SECURE_AUTH_SALT
		LOGGED_IN_SALT
		NONCE_SALT
	)
	envs=(
		WORDPRESS_DB_HOST
		WORDPRESS_DB_USER
		WORDPRESS_DB_PASSWORD
		WORDPRESS_DB_NAME
		WORDPRESS_DB_CHARSET
		WORDPRESS_DB_COLLATE
		"${uniqueEnvs[@]/#/WORDPRESS_}"
		WORDPRESS_TABLE_PREFIX
		WORDPRESS_DEBUG
		WORDPRESS_CONFIG_EXTRA
	)
	haveConfig=
	for e in "${envs[@]}"; do
		if [ -z "$haveConfig" ] && [ -n "${!e}" ]; then
			haveConfig=1
		fi
	done

	if [ "$haveConfig" ]; then
		: "${WORDPRESS_DB_HOST:=mysql}"
		: "${WORDPRESS_DB_USER:=root}"
		: "${WORDPRESS_DB_PASSWORD:=}"
		: "${WORDPRESS_DB_NAME:=wordpress}"
		: "${WORDPRESS_DB_CHARSET:=utf8}"
		: "${WORDPRESS_DB_COLLATE:=}"
		: "${WORDPRESS_DEBUG:=}"

		wp config create --dbname="$WORDPRESS_DB_NAME" --dbuser="$WORDPRESS_DB_USER" --dbpass="$WORDPRESS_DB_PASSWORD" --dbhost="$WORDPRESS_DB_HOST" --dbcharset="$WORDPRESS_DB_CHARSET" --dbcollate="$WORDPRESS_DB_COLLATE" --allow-root

		for unique in "${uniqueEnvs[@]}"; do
			uniqVar="WORDPRESS_$unique"
			if [ -n "${!uniqVar:-}" ]; then
				wp config set "$unique" "${!uniqVar}" --type=constant --allow-root
			else
				currentVal="$(sed -rn -e "s/define\((([\'\"])$unique\2\s*,\s*)(['\"])(.*)\3\);/\4/p" wp-config.php)"
				if [ "$currentVal" = 'put your unique phrase here' ]; then
					wp config set "$unique" "$(head -c1m /dev/urandom | sha1sum | cut -d' ' -f1)" --allow-root
				fi
			fi
		done

		if [ -n "$WORDPRESS_DEBUG" ]; then
			wp config set WP_DEBUG true --type=constant --raw --allow-root
		fi
	fi

	chown -R "$user:$group" .

	: "${WORDPRESS_BLOG_NAME:=WordPress}"
	: "${WORDPRESS_BLOG_USER:=admin}"
	: "${WORDPRESS_BLOG_PASS:=password}"
	: "${WORDPRESS_BLOG_EMAIL:=root@localhost}"
	: "${WORDPRESS_BLOG_URL:=example.com}"

	wp db drop --yes --allow-root || true
	wp db create --allow-root || true
	wp core multisite-install --url="$WORDPRESS_BLOG_URL" --title="$WORDPRESS_BLOG_NAME" --admin_user="$WORDPRESS_BLOG_USER" --admin_password="$WORDPRESS_BLOG_PASS" --admin_email="$WORDPRESS_BLOG_EMAIL" --allow-root

	for e in "${envs[@]}"; do
		unset "$e"
	done
fi

exec "$@"