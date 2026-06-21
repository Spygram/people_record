const express = require('express');
const { Pool } = require('pg');
const path = require('path');
const cors = require('cors');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const app = express();
const port = process.env.PORT || 3000;

/* ------------------ DB CONNECTION ------------------ */
const pool = new Pool({
  user: process.env.DB_USER,
  host: process.env.DB_HOST,   
  database: process.env.DB_NAME,
  password: process.env.DB_PASSWORD,
  port: parseInt(process.env.DB_PORT, 10),
  ssl: {
    rejectUnauthorized: false,
  },
});

/* ------------------ DB INIT (IMPORTANT PART) ------------------ */
/*async function initDb() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS person (
        serial_number SERIAL PRIMARY KEY,
        name TEXT,
        age INT
      )
    `);

    console.log('✅ Database initialized (person table ready)');
  } catch (err) {
    console.error('❌ Database initialization failed', err);
    process.exit(1); // stop app if DB is broken
  }
}*/ //init check1
async function initDb(retries = 10, delay = 3000) {
  while (retries) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS person (
          serial_number SERIAL PRIMARY KEY,
          name TEXT,
          age INT
        )
      `);

      console.log('✅ Database initialized (person table ready)');
      return;
    } 
    catch (err) {
      // retries--;
      // console.log(`⏳ Waiting for database... retries left: ${retries}`);
      // await new Promise(res => setTimeout(res, delay));
      retries--;

      console.error("❌ Database connection error:");
      console.error(err);
      console.error("Message:", err.message);

      console.log(`⏳ Waiting for database... retries left: ${retries}`);
      await new Promise(res => setTimeout(res, delay));
    }
  }

  console.error('❌ Could not connect to database after retries');
  process.exit(1);
}


/* ------------------ MIDDLEWARE ------------------ */
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static('public'));
app.use(cors());
/* ------------------ ROUTES ------------------ */
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

app.get('/people', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM person ORDER BY serial_number'
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).send('Error fetching people');
  }
});

app.post('/submit', async (req, res) => {
  const { name, age } = req.body;
  try {
    await pool.query(
      'INSERT INTO person (name, age) VALUES ($1, $2)',
      [name, age]
    );
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false });
  }
});

app.post('/delete', async (req, res) => {
  const { id } = req.body;
  try {
    await pool.query(
      'DELETE FROM person WHERE serial_number = $1',
      [id]
    );
    res.json({ success: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false });
  }
});

/* ------------------ START SERVER ------------------ */
(async () => {
  await initDb();   // 👈 DB schema guaranteed
  app.listen(port, () => {
    console.log(`🚀 Server running at http://localhost:${port}`);
  });
})();
