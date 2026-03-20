import axios from 'axios';
import { searchImages } from './researchService.js';

export type EbookImageSource = 'web' | 'ai' | 'auto';
export type EbookResolvedImageSource = 'web' | 'generated';

export interface ResolveEbookImageOptions {
  prompt: string;
  queries: string[];
  source: EbookImageSource;
  imageModel?: string;
  imageApiKey?: string;
  aspectRatio?: string;
}

export interface ResolvedEbookImage {
  url: string;
  source: EbookResolvedImageSource;
}

class EbookImageService {
  async resolveImage(
    options: ResolveEbookImageOptions,
  ): Promise<ResolvedEbookImage | null> {
    const normalizedSource = options.source;

    if (
      (normalizedSource === 'ai' || normalizedSource === 'auto') &&
      options.imageModel
    ) {
      const aiImage = await this.generateImageWithOpenRouter(options);
      if (aiImage) {
        return { url: aiImage, source: 'generated' };
      }

      if (normalizedSource === 'ai') {
        return null;
      }
    }

    if (normalizedSource === 'web' || normalizedSource === 'auto') {
      const webImage = await this.searchWebImage(options.queries);
      if (webImage) {
        return { url: webImage, source: 'web' };
      }
    }

    return null;
  }

  private async generateImageWithOpenRouter(
    options: ResolveEbookImageOptions,
  ): Promise<string | null> {
    const apiKey =
      (options.imageApiKey ?? '').trim() || process.env.OPENROUTER_API_KEY || '';

    if (!apiKey || !options.imageModel) {
      return null;
    }

    try {
      const response = await axios.post(
        'https://openrouter.ai/api/v1/chat/completions',
        {
          model: options.imageModel,
          messages: [
            {
              role: 'user',
              content: options.prompt,
            },
          ],
          modalities: ['image', 'text'],
          image_config: {
            aspect_ratio: options.aspectRatio || '1:1',
          },
          max_tokens: 4096,
        },
        {
          timeout: 120000,
          headers: {
            Authorization: `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://noteclaw.app',
            'X-Title': 'NoteClaw Ebook Images',
          },
        },
      );

      return this.extractImageFromOpenRouterResponse(response.data);
    } catch (error: any) {
      console.warn(
        '[EbookImageService] AI image generation failed:',
        error?.response?.data || error?.message || error,
      );
      return null;
    }
  }

  private extractImageFromOpenRouterResponse(data: any): string | null {
    const message = data?.choices?.[0]?.message;
    if (!message) {
      return null;
    }

    const messageImages = Array.isArray(message.images) ? message.images : [];
    for (const image of messageImages) {
      const url = image?.image_url?.url;
      if (this.isUsableImageUrl(url)) {
        return url;
      }
    }

    const content = message.content;
    if (Array.isArray(content)) {
      for (const part of content) {
        if (part?.type === 'image_url' && this.isUsableImageUrl(part?.image_url?.url)) {
          return part.image_url.url;
        }
      }
    }

    if (typeof content === 'string' && content.trim()) {
      const base64Match = content.match(/data:image\/[^;]+;base64,[A-Za-z0-9+/=]+/);
      if (base64Match) {
        return base64Match[0];
      }

      const urlMatch = content.match(
        /https?:\/\/[^\s"')]+?\.(png|jpg|jpeg|gif|webp)/i,
      );
      if (urlMatch && this.isUsableImageUrl(urlMatch[0])) {
        return urlMatch[0];
      }
    }

    return null;
  }

  private async searchWebImage(queries: string[]): Promise<string | null> {
    for (const query of queries.map((value) => value.trim()).filter(Boolean)) {
      try {
        const results = await searchImages(query, 6);
        const firstValidImage = results.find((candidate) =>
          this.isUsableImageUrl(candidate),
        );

        if (firstValidImage) {
          return firstValidImage;
        }
      } catch (error) {
        console.warn('[EbookImageService] Web image search failed:', error);
      }
    }

    return null;
  }

  private isUsableImageUrl(value: unknown): value is string {
    if (typeof value !== 'string') {
      return false;
    }

    const trimmed = value.trim();
    return /^https?:\/\//i.test(trimmed) || /^data:image\//i.test(trimmed);
  }
}

export const ebookImageService = new EbookImageService();
export default ebookImageService;
