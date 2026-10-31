# Conéctate al VPS
ssh usuario@tu-servidor

# Descarga el zip
wget https://genarogg.github.io/media/server/ban-bot/ban-bot-package.zip

# Si no tienes unzip instalado
sudo apt install -y unzip

# Descomprime
unzip ban-bot-package.zip
cd ban-bot-package

# Dale permisos y ejecuta el instalador
chmod +x install-ban-bot.sh
sudo ./install-ban-bot.sh

# Como bloquear un user-agent
sudo ban-bot --ban "SemrushBot"

# Listar los user-agents bloqueados
sudo ban-bot --list

# Eliminar un bloqueo
sudo ban-bot --delete "SemrushBot"

# Verificar que el bloqueo funciona (debería devolver HTTP/2 403)
curl -A "Mozilla/5.0 (compatible; SemrushBot/7~bl)" -I https://eltubazodigital.com