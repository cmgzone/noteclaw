import { GoogleGenerativeAI } from '@google/generative-ai';
import axios from 'axios';
import dotenv from 'dotenv';

dotenv.config();

// Initialize Gemini
const genAI = process.env.GEMINI_API_KEY
    ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY)
    : null;

function getGeminiClient(apiKey?: string): GoogleGenerativeAI {
    const key = (apiKey ?? '').trim();
    if (key) return new GoogleGenerativeAI(key);
    if (genAI) return genAI;
    throw new Error('Gemini API key not configured. Please add GEMINI_API_KEY to your environment or provide X-User-Api-Key.');
}

export interface ChatMessage {
    role: 'user' | 'assistant' | 'system' | 'model';
    content: string | Array<any>;
}

/**
 * Generate AI response using Gemini
 */
export async function generateWithGemini(
    messages: ChatMessage[],
    model: string = 'gemini-2.0-flash',
    apiKey?: string
): Promise<string> {
    console.log(`[Gemini] Generating response with model: ${model}`);

    // Create a timeout promise
    const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Gemini request timed out after 120s')), 120000);
    });

    try {
        const client = getGeminiClient(apiKey);
        const geminiModel = client.getGenerativeModel({ model });

        // Helper to convert content to Gemini parts
        const convertContent = (content: string | Array<any>) => {
            if (typeof content === 'string') return [{ text: content }];
            return content.map(part => {
                if (part.type === 'image_url') {
                    const matches = part.image_url.url.match(/^data:(.+);base64,(.+)$/);
                    if (matches) {
                        return { inlineData: { mimeType: matches[1], data: matches[2] } };
                    }
                }
                return { text: part.text || '' };
            });
        };

        // Convert messages to Gemini format
        const history = messages.slice(0, -1).map(msg => ({
            role: msg.role === 'assistant' ? 'model' : 'user',
            parts: convertContent(msg.content)
        }));

        const lastMessage = messages[messages.length - 1];

        const chat = geminiModel.startChat({
            history: history.length > 0 ? history : undefined,
        });

        // Race between the actual request and timeout
        const result = await Promise.race([
            chat.sendMessage(convertContent(lastMessage.content)),
            timeoutPromise
        ]);

        return result.response.text();
    } catch (error: any) {
        console.error('Gemini error:', error);
        throw new Error(`Gemini API error: ${error.message}`);
    }
}

/**
 * Generate AI response using OpenRouter
 */
export async function generateWithOpenRouter(
    messages: ChatMessage[],
    model: string = 'meta-llama/llama-3.3-70b-instruct',
    maxTokens: number = 4096,
    apiKeyOverride?: string
): Promise<string> {
    const apiKey = (apiKeyOverride ?? '').trim() || process.env.OPENROUTER_API_KEY;

    if (!apiKey) {
        throw new Error('OpenRouter API key not configured. Please add OPENROUTER_API_KEY or provide X-User-Api-Key.');
    }

    try {
        // Convert messages to OpenRouter format (supports multimodal)
        const convertedMessages = messages.map(msg => {
            // If content is already in multimodal format, keep it
            if (Array.isArray(msg.content)) {
                return {
                    role: msg.role === 'model' ? 'assistant' : msg.role,
                    content: msg.content.map(part => {
                        // Convert image_url format for OpenRouter
                        if (part.type === 'image_url') {
                            return {
                                type: 'image_url',
                                image_url: part.image_url
                            };
                        }
                        // Text part
                        return { type: 'text', text: part.text || part };
                    })
                };
            }
            // Simple text content with role mapping
            const role = msg.role === 'model' ? 'assistant' : msg.role;
            return { role, content: msg.content };
        });

        const response = await axios.post(
            'https://openrouter.ai/api/v1/chat/completions',
            {
                model,
                messages: convertedMessages,
                max_tokens: maxTokens,
            },
            {
                timeout: 120000, // 2 minute timeout
                headers: {
                    'Authorization': `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                    'HTTP-Referer': 'https://noteclaw.app',
                    'X-Title': 'NoteClaw'
                }
            }
        );

        return response.data.choices[0].message.content;
    } catch (error: any) {
        console.error('OpenRouter error:', error.response?.data || error);
        if (error.code === 'ECONNABORTED' || error.message?.includes('timeout')) {
            throw new Error('OpenRouter request timed out after 120s');
        }
        throw new Error(`OpenRouter API error: ${error.response?.data?.error?.message || error.message}`);
    }
}

/**
 * Stream AI response using Gemini
 */
export async function* streamWithGemini(
    messages: ChatMessage[],
    model: string = 'gemini-2.0-flash',
    apiKey?: string
): AsyncGenerator<string> {
    try {
        const client = getGeminiClient(apiKey);
        const geminiModel = client.getGenerativeModel({ model });

        // Helper to convert content to Gemini parts
        const convertContent = (content: string | Array<any>) => {
            if (typeof content === 'string') return [{ text: content }];
            return content.map(part => {
                if (part.type === 'image_url') {
                    const matches = part.image_url.url.match(/^data:(.+);base64,(.+)$/);
                    if (matches) {
                        return { inlineData: { mimeType: matches[1], data: matches[2] } };
                    }
                }
                return { text: part.text || '' };
            });
        };

        const history = messages.slice(0, -1).map(msg => ({
            role: msg.role === 'assistant' ? 'model' : 'user',
            parts: convertContent(msg.content)
        }));

        const lastMessage = messages[messages.length - 1];

        const chat = geminiModel.startChat({
            history: history.length > 0 ? history : undefined,
        });

        const result = await chat.sendMessageStream(convertContent(lastMessage.content));

        for await (const chunk of result.stream) {
            const text = chunk.text();
            if (text) {
                yield text;
            }
        }
    } catch (error: any) {
        console.error('Gemini streaming error:', error);
        throw new Error(`Gemini streaming error: ${error.message}`);
    }
}

/**
 * Stream AI response using OpenRouter
 */
export async function* streamWithOpenRouter(
    messages: ChatMessage[],
    model: string = 'meta-llama/llama-3.3-70b-instruct',
    maxTokens: number = 4096,
    apiKeyOverride?: string
): AsyncGenerator<string> {
    const apiKey = (apiKeyOverride ?? '').trim() || process.env.OPENROUTER_API_KEY;

    if (!apiKey) {
        throw new Error('OpenRouter API key not configured. Please add OPENROUTER_API_KEY or provide X-User-Api-Key.');
    }

    try {
        // Convert messages to OpenRouter format (supports multimodal)
        const convertedMessages = messages.map(msg => {
            // If content is already in multimodal format, keep it
            if (Array.isArray(msg.content)) {
                return {
                    role: msg.role,
                    content: msg.content.map(part => {
                        // Convert image_url format for OpenRouter
                        if (part.type === 'image_url') {
                            return {
                                type: 'image_url',
                                image_url: part.image_url
                            };
                        }
                        // Text part
                        return { type: 'text', text: part.text || part };
                    })
                };
            }
            // Simple text content with role mapping
            const role = msg.role === 'model' ? 'assistant' : msg.role;
            return { role, content: msg.content };
        });

        // Log payload for debugging
        console.log('[OpenRouter] Streaming request:', {
            model,
            messageCount: convertedMessages.length,
            roles: convertedMessages.map(m => m.role),
            firstMessageContent: convertedMessages[0]?.content?.toString().substring(0, 50)
        });

        const response = await axios.post(
            'https://openrouter.ai/api/v1/chat/completions',
            {
                model,
                messages: convertedMessages,
                stream: true,
                max_tokens: maxTokens,
            },
            {
                responseType: 'stream',
                headers: {
                    'Authorization': `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                    'HTTP-Referer': 'https://noteclaw.app',
                    'X-Title': 'NoteClaw'
                }
            }
        );

        const stream = response.data;
        let buffer = '';

        for await (const chunk of stream) {
            const chunkStr = chunk.toString();
            buffer += chunkStr;

            const lines = buffer.split('\n');
            // Process all complete lines
            for (let i = 0; i < lines.length - 1; i++) {
                const line = lines[i].trim();
                if (line.startsWith('data: ')) {
                    const dataStr = line.slice(6);
                    if (dataStr === '[DONE]') continue;

                    try {
                        const data = JSON.parse(dataStr);
                        const content = data.choices?.[0]?.delta?.content;
                        if (content) {
                            yield content;
                        }
                    } catch (e) {
                        // Ignore parse errors for partial lines
                    }
                }
            }
            // Keep the last partial line in buffer
            buffer = lines[lines.length - 1];
            
            // Prevent buffer from growing too large
            if (buffer.length > 10000) {
                buffer = buffer.slice(-5000);
            }
        }
        
        // Clear buffer to free memory
        buffer = '';
    } catch (error: any) {
        console.error('OpenRouter streaming error:', error.message);
        // Try to read error response body if available
        if (error.response?.data) {
            let errorBody = '';
            try {
                // For stream responses, we need to read the data
                const stream = error.response.data;
                for await (const chunk of stream) {
                    errorBody += chunk.toString();
                }
                console.error('[OpenRouter] Error response body:', errorBody);
            } catch (e) {
                console.error('[OpenRouter] Could not read error body');
            }
        }
        throw new Error(`OpenRouter streaming error: ${error.message}`);
    }
}

/**
 * Generic AI generation with provider selection
 */
export async function generateResponse(
    messages: ChatMessage[],
    provider: 'gemini' | 'openrouter' | 'openai' = 'gemini',
    model?: string
): Promise<string> {
    if (provider === 'openrouter') {
        return generateWithOpenRouter(messages, model); // model defaults in function if undefined
    } else {
        // Default to Gemini
        return generateWithGemini(messages, model); // model defaults in function if undefined
    }
}

/**
 * Generate content summary using AI
 */
export async function generateSummary(
    content: string,
    provider: 'gemini' | 'openrouter' = 'gemini',
    model?: string
): Promise<string> {
    // Limit content to prevent memory issues (50KB max)
    const truncatedContent = content.substring(0, 50000);
    
    const messages: ChatMessage[] = [
        {
            role: 'system',
            content: 'You are a helpful assistant that creates concise, informative summaries of content. Focus on key points and main ideas.'
        },
        {
            role: 'user',
            content: `Please create a comprehensive summary of the following content:\n\n${truncatedContent}`
        }
    ];

    return generateResponse(messages, provider, model);
}

/**
 * Generate question suggestions based on content
 */
export async function generateQuestions(
    content: string,
    count: number = 5
): Promise<string[]> {
    // Limit content to prevent memory issues (30KB max)
    const truncatedContent = content.substring(0, 30000);
    
    const messages: ChatMessage[] = [
        {
            role: 'system',
            content: 'You are a helpful assistant that generates insightful questions about content to help users learn and understand better.'
        },
        {
            role: 'user',
            content: `Generate ${count} thoughtful questions that could be asked about the following content. Return only the questions, one per line, without numbering:\n\n${truncatedContent}`
        }
    ];

    const response = await generateWithGemini(messages);
    return response
        .split('\n')
        .map(q => q.trim())
        .filter(q => q.length > 0 && q.endsWith('?'))
        .slice(0, count);
}

/**
 * Generate flashcards from content
 */
export async function generateFlashcards(
    content: string,
    count: number = 10
): Promise<Array<{ question: string; answer: string }>> {
    // Limit content to prevent memory issues (30KB max)
    const truncatedContent = content.substring(0, 30000);
    
    const messages: ChatMessage[] = [
        {
            role: 'system',
            content: 'You are an expert educator creating flashcards for effective learning.'
        },
        {
            role: 'user',
            content: `Create ${count} flashcards from this content. Return as JSON array with "question" and "answer" fields:\n\n${truncatedContent}`
        }
    ];

    const response = await generateWithGemini(messages);

    try {
        const jsonMatch = response.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
            return JSON.parse(jsonMatch[0]);
        }
    } catch (e) {
        console.error('Failed to parse flashcards:', e);
    }

    return [];
}

/**
 * Generate embedding for text using Gemini
 */
export async function generateEmbedding(text: string): Promise<number[]> {
    if (!genAI) {
        throw new Error('Gemini API key not configured');
    }

    try {
        const model = genAI.getGenerativeModel({ model: "text-embedding-004" });
        const result = await model.embedContent(text);
        return result.embedding.values;
    } catch (error: any) {
        console.error('Embedding generation error:', error);
        // Fallback or rethrow
        throw new Error(`Failed to generate embedding: ${error.message}`);
    }
}

/**
 * Generate quiz questions from content
 */
export async function generateQuiz(
    content: string,
    count: number = 5
): Promise<Array<{
    question: string;
    options: string[];
    correctIndex: number;
    explanation: string;
}>> {
    // Limit content to prevent memory issues (30KB max)
    const truncatedContent = content.substring(0, 30000);
    
    const messages: ChatMessage[] = [
        {
            role: 'system',
            content: 'You are an expert educator creating multiple-choice quiz questions.'
        },
        {
            role: 'user',
            content: `Create ${count} multiple-choice questions from this content. Each should have 4 options. Return as JSON array with fields: "question", "options" (array of 4 strings), "correctIndex" (0-3), "explanation":\n\n${truncatedContent}`
        }
    ];

    const response = await generateWithGemini(messages);

    try {
        const jsonMatch = response.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
            return JSON.parse(jsonMatch[0]);
        }
    } catch (e) {
        console.error('Failed to parse quiz:', e);
    }

    return [];
}
