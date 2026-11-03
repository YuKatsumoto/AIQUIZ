// テスト用の偽の Anthropic クライアント。受け取ったパラメータを記録し、決めた返事を返す。
const USAGE = { input_tokens: 2000, output_tokens: 500, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 };

function message({ text = '[]', stop_reason = 'end_turn', model = 'claude-sonnet-5-5', usage = USAGE } = {}) {
    return { model, stop_reason, usage, content: [{ type: 'thinking', thinking: '' }, { type: 'text', text }] };
}

class FakeStream {
    constructor(reply) {
        this.reply = reply;
        this.aborted = false;
        this.currentMessage = undefined;
    }

    async *[Symbol.asyncIterator]() {
        if (this.reply.error) throw this.reply.error;
        const final = message(this.reply);
        this.currentMessage = { ...final, content: [] };
        yield { type: 'message_start', message: this.currentMessage };
        yield { type: 'content_block_delta', index: 0, delta: { type: 'thinking_delta', thinking: '' } };
        for (const piece of this.reply.pieces || [final.content[1].text]) {
            yield { type: 'content_block_delta', index: 1, delta: { type: 'text_delta', text: piece } };
        }
        if (this.reply.errorAfterText) throw this.reply.errorAfterText;
        yield { type: 'message_stop' };
    }

    async finalMessage() {
        return message(this.reply);
    }

    abort() {
        this.aborted = true;
    }
}

function fakeAnthropic(reply = {}) {
    const calls = [];
    const client = {
        calls,
        reply,
        beta: {
            messages: {
                create: async params => {
                    calls.push({ kind: 'create', params });
                    if (client.reply.error) throw client.reply.error;
                    return message(client.reply);
                },
                stream: params => {
                    calls.push({ kind: 'stream', params });
                    return new FakeStream(client.reply);
                },
            },
        },
    };
    return client;
}

function apiError(status, text = 'error') {
    const error = new Error(text);
    error.status = status;
    return error;
}

module.exports = { USAGE, apiError, fakeAnthropic, message };
