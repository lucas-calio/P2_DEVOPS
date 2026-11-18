const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');

const PORT = Number(process.env.PORT) || 3000;

// ---------------------------------------------------------------------------
// CORS: permite somente a origem da aplicação web (VM1), métodos GET e POST.
// O preflight (OPTIONS) é respondido automaticamente pelo middleware.
// CORS_ORIGIN aceita uma ou mais origens separadas por vírgula.
// ---------------------------------------------------------------------------
const allowedOrigins = (process.env.CORS_ORIGIN || '')
  .split(',')
  .map((o) => o.trim().replace(/\/$/, ''))
  .filter(Boolean);

const corsOptions = {
  origin(origin, callback) {
    // Requisições sem cabeçalho Origin (curl, health check) não são do navegador
    if (!origin || allowedOrigins.includes(origin)) return callback(null, true);
    console.warn(`CORS: origem bloqueada -> ${origin}`);
    return callback(null, false);
  },
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type'],
  optionsSuccessStatus: 204,
};

const app = express();
app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json());

// ---------------------------------------------------------------------------
// MySQL
// ---------------------------------------------------------------------------
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'mysql',
  port: Number(process.env.DB_PORT) || 3306,
  user: process.env.DB_USER || 'cursos',
  password: process.env.DB_PASSWORD || 'cursos123',
  database: process.env.DB_NAME || 'cursosdb',
  waitForConnections: true,
  connectionLimit: 10,
  decimalNumbers: true,
});

async function initDb() {
  const maxTentativas = 40;
  for (let tentativa = 1; tentativa <= maxTentativas; tentativa++) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS cursos (
          id         INT AUTO_INCREMENT PRIMARY KEY,
          nome       VARCHAR(255)  NOT NULL,
          instrutor  VARCHAR(255)  NOT NULL,
          preco      DECIMAL(10,2) NOT NULL,
          vagas      INT           NOT NULL,
          criado_em  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
      console.log('MySQL conectado e tabela "cursos" pronta.');
      return;
    } catch (err) {
      console.log(`Aguardando MySQL (${tentativa}/${maxTentativas}): ${err.code || err.message}`);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  throw new Error('Não foi possível conectar ao MySQL.');
}

// ---------------------------------------------------------------------------
// Rotas
// ---------------------------------------------------------------------------

// POST /curso - recebe os quatro campos e cadastra no MySQL
app.post('/curso', async (req, res) => {
  const { nome, instrutor, preco, vagas } = req.body || {};

  const nomeTxt = typeof nome === 'string' ? nome.trim() : '';
  const instrutorTxt = typeof instrutor === 'string' ? instrutor.trim() : '';
  const precoNum = Number(String(preco ?? '').replace(',', '.'));
  const vagasNum = Number(vagas);

  const erros = [];
  if (!nomeTxt) erros.push('nome do curso é obrigatório (texto)');
  if (!instrutorTxt) erros.push('instrutor responsável é obrigatório (texto)');
  if (preco === undefined || preco === null || preco === '' || !Number.isFinite(precoNum) || precoNum < 0)
    erros.push('preço deve ser um número decimal >= 0');
  if (vagas === undefined || vagas === null || vagas === '' || !Number.isInteger(vagasNum) || vagasNum < 0)
    erros.push('quantidade de vagas deve ser um número inteiro >= 0');

  if (erros.length) return res.status(400).json({ erro: 'Dados inválidos', detalhes: erros });

  try {
    const [result] = await pool.execute(
      'INSERT INTO cursos (nome, instrutor, preco, vagas) VALUES (?, ?, ?, ?)',
      [nomeTxt, instrutorTxt, precoNum.toFixed(2), vagasNum]
    );
    return res.status(201).json({
      id: result.insertId,
      nome: nomeTxt,
      instrutor: instrutorTxt,
      preco: Number(precoNum.toFixed(2)),
      vagas: vagasNum,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ erro: 'Erro ao cadastrar curso' });
  }
});

// GET /cursos - retorna todos os cursos em JSON
app.get('/cursos', async (_req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, nome, instrutor, preco, vagas, criado_em FROM cursos ORDER BY id'
    );
    return res.json(rows);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ erro: 'Erro ao listar cursos' });
  }
});

// Health check (usado pelo Ansible)
app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok' });
  } catch {
    res.status(503).json({ status: 'erro', banco: 'indisponível' });
  }
});

// JSON inválido no corpo da requisição
app.use((err, _req, res, next) => {
  if (err.type === 'entity.parse.failed') return res.status(400).json({ erro: 'JSON inválido' });
  return next(err);
});

initDb()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`API de cursos rodando na porta ${PORT}`);
      console.log(`CORS - origens permitidas: ${allowedOrigins.join(', ') || '(nenhuma)'}`);
    });
  })
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
