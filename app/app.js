// Funções compartilhadas pelas páginas
const API_URL = (window.API_URL || 'http://localhost:3000').replace(/\/$/, '');

function mostrarMensagem(texto, tipo) {
  const el = document.getElementById('mensagem');
  el.textContent = texto;
  el.className = `mensagem ${tipo}`;
}

function formatarPreco(valor) {
  return Number(valor).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
}
