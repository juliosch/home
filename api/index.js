import express from 'express';
import cors from 'cors';
import { controlWiz } from '../js/control-wiz.js';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ message: controlWiz(req.query.ip, req.query.brightness, req.query.temperature, req.query.status) })
});

// Start server
const PORT = process.env.PORT || 19999;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`)
});
