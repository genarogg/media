# Conéctate al VPS
ssh usuario@tu-servidor

# Descarga el zip
wget https://genarogg.github.io/media/server/ban-ip/ban-ip-package.zip

# Si no tienes unzip instalado
sudo apt install -y unzip

# Descomprime
unzip ban-ip-package.zip
cd ban-ip-package

# Dale permisos y ejecuta el instalador
chmod +x install-ban-ip.sh
sudo ./install-ban-ip.sh

# como bloquear ip ban-ip --ban 34.23.118.234