const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors());
// すべてのリクエストボディをテキストとして受け取る
app.use(express.text({ type: '*/*' }));

app.post('/openai', async (req, res) => {
    try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
            },
            body: req.body
        });
        const data = await response.text();
        res.status(response.status).send(data);
    } catch (err) {
        res.status(500).send("Proxy Error: " + err.message);
    }
});

app.post('/gemini', async (req, res) => {
    try {
        const model = req.query.model || 'gemini-2.5-flash';
        const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${process.env.GEMINI_API_KEY}`;
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: req.body
        });
        const data = await response.text();
        res.status(response.status).send(data);
    } catch (err) {
        res.status(500).send("Proxy Error: " + err.message);
    }
});

app.get('/', (req, res) => {
    res.send('AIQUIZ Proxy Server is running! (Native Fetch v2)');
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
    console.log(`Proxy listening on port ${PORT}`);
});
