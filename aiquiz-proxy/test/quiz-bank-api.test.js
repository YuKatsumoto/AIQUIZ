const test = require('node:test');
const assert = require('node:assert/strict');

process.env.APP_SECRET = 'test-app-secret';
const { app } = require('../index');

async function withServer(callback) {
    const server = app.listen(0, '127.0.0.1');
    await new Promise(resolve => server.once('listening', resolve));
    try {
        const address = server.address();
        await callback(`http://127.0.0.1:${address.port}`);
    } finally {
        await new Promise(resolve => server.close(resolve));
    }
}

test('quiz bank endpoints require the existing app secret', async () => {
    await withServer(async base => {
        const response = await fetch(`${base}/quiz-bank/snapshot`);
        assert.equal(response.status, 403);
    });
});

test('candidate endpoint rejects malformed batches before touching Firebase', async () => {
    await withServer(async base => {
        const response = await fetch(`${base}/quiz-bank/candidates`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-App-Secret': 'test-app-secret',
            },
            body: JSON.stringify({ items: [] }),
        });
        assert.equal(response.status, 400);
        assert.match((await response.json()).error, /1-50/);
    });
});
