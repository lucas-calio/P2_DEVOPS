FROM nginx:alpine

# Página HTML + arquivos estáticos servidos pelo nginx
COPY index.html cursos.html style.css app.js config.js /usr/share/nginx/html/

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
