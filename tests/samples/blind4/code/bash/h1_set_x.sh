set -x
rsync -avz --delete ./build/ deploy@web01:/var/www/app/