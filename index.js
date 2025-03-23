const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

const { execSync } = require('child_process');

function switchBulb(ip, on) {
  const socat = `socat - UDP-DATAGRAM:${ip}:38899`

  const cmdToggle = {
    "method":"setPilot",
    "params":{
      "state": on
    }
  }

  const toggle = execSync(`echo '${JSON.stringify(cmdToggle)}' | ${socat}`)
  return toggle.toString()
}

app.get('/', (req, res) => {
  res.json({ message: switchBulb(req.query.ip, +req.query.on) })
});

// Start server
const PORT = process.env.PORT || 19999;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`)
})
