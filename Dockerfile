# Use a imagem oficial do Nextcloud com Apache
FROM nextcloud:apache

# Instale extensões PHP necessárias para produção (exemplo: PostgreSQL, GD, ZIP)
RUN apt-get update && apt-get install -y \
    libpq-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    unzip \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install gd pdo pdo_pgsql zip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copie arquivos de configuração customizados (opcional)
# COPY config.php /var/www/html/config/config.php

# Ajuste permissões (importante para ECS e volumes)
RUN chown -R www-data:www-data /var/www/html

# Exponha a porta 80 (Apache)
EXPOSE 80

# Comando padrão já vem da imagem oficial
# CMD ["apache2-foreground"]