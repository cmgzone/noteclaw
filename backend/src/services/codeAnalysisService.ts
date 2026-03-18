/**
 * Code Analysis Service
 * Provides comprehensive code analysis for GitHub sources
 * 
 * Features:
 * - Code explanation and documentation
 * - Quality rating (1-10 scale)
 * - Architecture analysis
 * - Best practices evaluation
 * - Security assessment
 * - Performance insights
 * 
 * This analysis improves fact-checking results for code sources
 * by providing the AI with deep knowledge about the codebase.
 * 
 * Supports admin-configured AI models from the database.
 * Users can select which model to use for analysis.
 */

import { GoogleGenerativeAI } from '@google/generative-ai';
import axios from 'axios';
import pool from '../config/database.js';

// ==================== INTERFACES ====================

export interface CodeAnalysisRequest {
  code: string;
  language: string;
  filePath: string;
  repoContext?: {
    owner: string;
    repo: string;
    branch: string;
  };
  modelId?: string; // Optional: specific model to use for analysis
  userId?: string;  // Optional: user ID to check model access
}

export interface CodeAnalysisResult {
  // Overall rating (1-10)
  rating: number;
  ratingExplanation: string;
  
  // Code explanation
  summary: string;
  purpose: string;
  keyComponents: ComponentAnalysis[];
  
  // Quality metrics
  qualityMetrics: QualityMetrics;
  
  // Technical analysis
  architecture: ArchitectureAnalysis;
  dependencies: DependencyAnalysis;
  
  // Recommendations
  strengths: string[];
  improvements: string[];
  securityNotes: string[];
  
  // Metadata
  analyzedAt: string;
  language: string;
  linesOfCode: number;
  complexity: 'low' | 'medium' | 'high';
  analyzedBy: string; // Model ID or 'basic'
  provider: 'gemini' | 'openrouter' | 'basic';
  modelName?: string; // Human-readable model name
}

export interface ComponentAnalysis {
  name: string;
  type: 'function' | 'class' | 'interface' | 'constant' | 'module' | 'component' | 'other';
  description: string;
  lineRange?: { start: number; end: number };
}

export interface QualityMetrics {
  readability: number;      // 1-10
  maintainability: number;  // 1-10
  testability: number;      // 1-10
  documentation: number;    // 1-10
  errorHandling: number;    // 1-10
}

export interface ArchitectureAnalysis {
  pattern: string;          // e.g., "MVC", "Repository", "Service Layer"
  designPatterns: string[]; // Detected design patterns
  concerns: string[];       // Separation of concerns notes
}

export interface DependencyAnalysis {
  imports: string[];
  externalDependencies: string[];
  internalDependencies: string[];
}

// ==================== AI MODEL INTERFACE ====================

export interface AIModel {
  id: string;
  name: string;
  model_id: string;
  provider: 'gemini' | 'openrouter';
  description: string;
  context_window: number;
  is_active: boolean;
  is_premium: boolean;
}

// ==================== SERVICE CLASS ====================

class CodeAnalysisService {
  private genAI: GoogleGenerativeAI | null = null;
  private openRouterApiKey: string | null = null;
  private initialized = false;
  private defaultModelId: string | null = null;

  initialize() {
    // Initialize Gemini
    const geminiKey = process.env.GEMINI_API_KEY;
    if (geminiKey) {
      this.genAI = new GoogleGenerativeAI(geminiKey);
      console.log('✅ Code Analysis Service: Gemini initialized');
    }
    
    // Initialize OpenRouter
    this.openRouterApiKey = process.env.OPENROUTER_API_KEY || null;
    if (this.openRouterApiKey) {
      console.log('✅ Code Analysis Service: OpenRouter initialized');
    }
    
    if (!this.genAI && !this.openRouterApiKey) {
      console.warn('⚠️ Code Analysis Service: No AI provider configured (set GEMINI_API_KEY or OPENROUTER_API_KEY)');
    }
    
    this.initialized = true;
  }

  /**
   * Get available AI models for code analysis
   */
  async getAvailableModels(): Promise<AIModel[]> {
    try {
      const result = await pool.query(
        `SELECT id, name, model_id, provider, description, context_window, is_active, is_premium 
         FROM ai_models 
         WHERE is_active = true 
         ORDER BY provider, name`
      );
      return result.rows;
    } catch (error) {
      console.error('Error fetching AI models:', error);
      return [];
    }
  }

  /**
   * Get a specific model by ID
   */
  async getModel(modelId: string): Promise<AIModel | null> {
    try {
      const result = await pool.query(
        `SELECT id, name, model_id, provider, description, context_window, is_active, is_premium 
         FROM ai_models 
         WHERE model_id = $1 AND is_active = true`,
        [modelId]
      );
      return result.rows[0] || null;
    } catch (error) {
      console.error('Error fetching model:', error);
      return null;
    }
  }

  /**
   * Get the default model for code analysis (first active model)
   */
  async getDefaultModel(): Promise<AIModel | null> {
    try {
      // Prefer Gemini models for code analysis
      const result = await pool.query(
        `SELECT id, name, model_id, provider, description, context_window, is_active, is_premium 
         FROM ai_models 
         WHERE is_active = true 
         ORDER BY 
           CASE WHEN provider = 'gemini' THEN 0 ELSE 1 END,
           name
         LIMIT 1`
      );
      return result.rows[0] || null;
    } catch (error) {
      console.error('Error fetching default model:', error);
      return null;
    }
  }

  /**
   * Generate content using Gemini
   */
  private async generateWithGemini(prompt: string): Promise<string> {
    if (!this.genAI) {
      throw new Error('Gemini not configured');
    }
    
    const model = this.genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });
    const result = await model.generateContent(prompt);
    return result.response.text();
  }

  /**
   * Generate content using OpenRouter
   */
  private async generateWithOpenRouter(prompt: string): Promise<string> {
    if (!this.openRouterApiKey) {
      throw new Error('OpenRouter not configured');
    }
    
    const response = await axios.post(
      'https://openrouter.ai/api/v1/chat/completions',
      {
        model: 'meta-llama/llama-3.3-70b-instruct',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 4096,
      },
      {
        timeout: 120000,
        headers: {
          'Authorization': `Bearer ${this.openRouterApiKey}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://noteclaw.app',
          'X-Title': 'NoteClaw Code Analysis'
        }
      }
    );
    
    return response.data.choices[0].message.content;
  }

  /**
   * Generate content with automatic fallback between providers
   * Supports user-selected model from admin-configured models
   */
  private async generateContent(
    prompt: string, 
    modelId?: string
  ): Promise<{ text: string; provider: 'gemini' | 'openrouter' | 'basic'; modelName?: string }> {
    // If a specific model is requested, try to use it
    if (modelId) {
      const model = await this.getModel(modelId);
      if (model) {
        try {
          if (model.provider === 'gemini' && this.genAI) {
            const genModel = this.genAI.getGenerativeModel({ model: model.model_id });
            const result = await genModel.generateContent(prompt);
            return { text: result.response.text(), provider: 'gemini', modelName: model.name };
          } else if (model.provider === 'openrouter' && this.openRouterApiKey) {
            const response = await axios.post(
              'https://openrouter.ai/api/v1/chat/completions',
              {
                model: model.model_id,
                messages: [{ role: 'user', content: prompt }],
                max_tokens: 4096,
              },
              {
                timeout: 120000,
                headers: {
                  'Authorization': `Bearer ${this.openRouterApiKey}`,
                  'Content-Type': 'application/json',
                  'HTTP-Referer': 'https://noteclaw.app',
                  'X-Title': 'NoteClaw Code Analysis'
                }
              }
            );
            return { text: response.data.choices[0].message.content, provider: 'openrouter', modelName: model.name };
          }
        } catch (error: any) {
          console.log(`Selected model ${model.name} failed, falling back:`, error.message);
        }
      }
    }

    // Try Gemini first (default fallback)
    if (this.genAI) {
      try {
        const text = await this.generateWithGemini(prompt);
        return { text, provider: 'gemini', modelName: 'Gemini 1.5 Flash' };
      } catch (error: any) {
        console.log('Gemini failed, trying OpenRouter:', error.message);
      }
    }
    
    // Fallback to OpenRouter
    if (this.openRouterApiKey) {
      try {
        const text = await this.generateWithOpenRouter(prompt);
        return { text, provider: 'openrouter', modelName: 'Llama 3.3 70B' };
      } catch (error: any) {
        console.log('OpenRouter also failed:', error.message);
        throw error;
      }
    }
    
    throw new Error('No AI provider available');
  }

  /**
   * Analyze code and generate comprehensive analysis
   */
  async analyzeCode(request: CodeAnalysisRequest): Promise<CodeAnalysisResult> {
    const { code, language, filePath, repoContext, modelId, userId } = request;
    
    // Basic metrics
    const linesOfCode = code.split('\n').length;
    const complexity = this.assessComplexity(code);
    
    // If no AI available, return basic analysis
    if (!this.genAI && !this.openRouterApiKey) {
      return this.getBasicAnalysis(code, language, filePath, linesOfCode, complexity);
    }

    try {
      const contextInfo = repoContext 
        ? `Repository: ${repoContext.owner}/${repoContext.repo} (${repoContext.branch} branch)\n` 
        : '';
      
      const prompt = `You are an expert code reviewer and software architect. Analyze this ${language} code file and provide a comprehensive analysis.

${contextInfo}File: ${filePath}

\`\`\`${language}
${code.substring(0, 15000)}${code.length > 15000 ? '\n... (truncated)' : ''}
\`\`\`

Provide analysis in this exact JSON format:
{
  "rating": <number 1-10>,
  "ratingExplanation": "<2-3 sentences explaining the rating>",
  "summary": "<1-2 paragraph summary of what this code does>",
  "purpose": "<one sentence describing the main purpose>",
  "keyComponents": [
    {
      "name": "<component name>",
      "type": "<function|class|interface|constant|module|component|other>",
      "description": "<what it does>"
    }
  ],
  "qualityMetrics": {
    "readability": <1-10>,
    "maintainability": <1-10>,
    "testability": <1-10>,
    "documentation": <1-10>,
    "errorHandling": <1-10>
  },
  "architecture": {
    "pattern": "<detected architectural pattern or 'None detected'>",
    "designPatterns": ["<pattern1>", "<pattern2>"],
    "concerns": ["<separation of concerns notes>"]
  },
  "dependencies": {
    "imports": ["<import1>", "<import2>"],
    "externalDependencies": ["<external lib>"],
    "internalDependencies": ["<internal module>"]
  },
  "strengths": ["<strength1>", "<strength2>"],
  "improvements": ["<improvement1>", "<improvement2>"],
  "securityNotes": ["<security note if any>"]
}

Rating guidelines:
- 9-10: Excellent - Production-ready, well-documented, follows best practices
- 7-8: Good - Solid code with minor improvements possible
- 5-6: Average - Functional but needs refactoring
- 3-4: Below Average - Significant issues, needs work
- 1-2: Poor - Major problems, not recommended for production

Be thorough but concise. Focus on actionable insights.`;

      const { text, provider, modelName } = await this.generateContent(prompt, modelId);
      
      // Extract JSON from response
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const analysis = JSON.parse(jsonMatch[0]);
        
        return {
          rating: Math.min(10, Math.max(1, analysis.rating || 5)),
          ratingExplanation: analysis.ratingExplanation || 'Analysis completed',
          summary: analysis.summary || 'No summary available',
          purpose: analysis.purpose || 'Purpose not determined',
          keyComponents: analysis.keyComponents || [],
          qualityMetrics: {
            readability: analysis.qualityMetrics?.readability || 5,
            maintainability: analysis.qualityMetrics?.maintainability || 5,
            testability: analysis.qualityMetrics?.testability || 5,
            documentation: analysis.qualityMetrics?.documentation || 5,
            errorHandling: analysis.qualityMetrics?.errorHandling || 5,
          },
          architecture: {
            pattern: analysis.architecture?.pattern || 'Not detected',
            designPatterns: analysis.architecture?.designPatterns || [],
            concerns: analysis.architecture?.concerns || [],
          },
          dependencies: {
            imports: analysis.dependencies?.imports || [],
            externalDependencies: analysis.dependencies?.externalDependencies || [],
            internalDependencies: analysis.dependencies?.internalDependencies || [],
          },
          strengths: analysis.strengths || [],
          improvements: analysis.improvements || [],
          securityNotes: analysis.securityNotes || [],
          analyzedAt: new Date().toISOString(),
          language,
          linesOfCode,
          complexity,
          analyzedBy: modelName || provider,
          provider,
          modelName,
        };
      }
    } catch (error) {
      console.error('Code analysis error:', error);
    }

    // Fallback to basic analysis
    return this.getBasicAnalysis(code, language, filePath, linesOfCode, complexity);
  }

  /**
   * Generate a fact-check friendly summary of the code
   * This is used to enhance fact-checking results
   */
  async generateFactCheckContext(analysis: CodeAnalysisResult): Promise<string> {
    const qualityAvg = (
      analysis.qualityMetrics.readability +
      analysis.qualityMetrics.maintainability +
      analysis.qualityMetrics.testability +
      analysis.qualityMetrics.documentation +
      analysis.qualityMetrics.errorHandling
    ) / 5;

    return `
## Code Analysis Summary

**Purpose:** ${analysis.purpose}

**Overall Rating:** ${analysis.rating}/10 - ${analysis.ratingExplanation}

**Summary:** ${analysis.summary}

**Key Components:**
${analysis.keyComponents.map(c => `- ${c.name} (${c.type}): ${c.description}`).join('\n')}

**Quality Metrics:**
- Readability: ${analysis.qualityMetrics.readability}/10
- Maintainability: ${analysis.qualityMetrics.maintainability}/10
- Testability: ${analysis.qualityMetrics.testability}/10
- Documentation: ${analysis.qualityMetrics.documentation}/10
- Error Handling: ${analysis.qualityMetrics.errorHandling}/10
- Average Quality: ${qualityAvg.toFixed(1)}/10

**Architecture:** ${analysis.architecture.pattern}
${analysis.architecture.designPatterns.length > 0 ? `Design Patterns: ${analysis.architecture.designPatterns.join(', ')}` : ''}

**Strengths:**
${analysis.strengths.map(s => `- ${s}`).join('\n')}

**Areas for Improvement:**
${analysis.improvements.map(i => `- ${i}`).join('\n')}

${analysis.securityNotes.length > 0 ? `**Security Notes:**\n${analysis.securityNotes.map(n => `- ${n}`).join('\n')}` : ''}

**Technical Details:**
- Language: ${analysis.language}
- Lines of Code: ${analysis.linesOfCode}
- Complexity: ${analysis.complexity}
- Analyzed by: ${analysis.analyzedBy}
- Analyzed: ${analysis.analyzedAt}
`.trim();
  }


  /**
   * Basic analysis when AI is not available
   */
  private getBasicAnalysis(
    code: string, 
    language: string, 
    filePath: string,
    linesOfCode: number,
    complexity: 'low' | 'medium' | 'high'
  ): CodeAnalysisResult {
    const imports = this.extractImports(code, language);
    const components = this.extractBasicComponents(code, language);
    
    return {
      rating: 5,
      ratingExplanation: 'Basic analysis performed without AI. Manual review recommended.',
      summary: `${language} file with ${linesOfCode} lines of code.`,
      purpose: `Code file: ${filePath}`,
      keyComponents: components,
      qualityMetrics: {
        readability: 5,
        maintainability: 5,
        testability: 5,
        documentation: this.hasDocumentation(code) ? 7 : 3,
        errorHandling: this.hasErrorHandling(code, language) ? 7 : 3,
      },
      architecture: {
        pattern: 'Not analyzed',
        designPatterns: [],
        concerns: [],
      },
      dependencies: {
        imports,
        externalDependencies: [],
        internalDependencies: [],
      },
      strengths: [],
      improvements: ['Enable AI analysis for detailed recommendations (set GEMINI_API_KEY or OPENROUTER_API_KEY)'],
      securityNotes: [],
      analyzedAt: new Date().toISOString(),
      language,
      linesOfCode,
      complexity,
      analyzedBy: 'basic',
      provider: 'basic',
      modelName: undefined,
    };
  }

  /**
   * Assess code complexity
   */
  private assessComplexity(code: string): 'low' | 'medium' | 'high' {
    const lines = code.split('\n').length;
    const nestingLevel = this.calculateMaxNesting(code);
    
    if (lines > 500 || nestingLevel > 6) return 'high';
    if (lines > 100 || nestingLevel > 4) return 'medium';
    return 'low';
  }

  /**
   * Calculate maximum nesting level
   */
  private calculateMaxNesting(code: string): number {
    let maxNesting = 0;
    let currentNesting = 0;
    
    for (const char of code) {
      if (char === '{' || char === '(' || char === '[') {
        currentNesting++;
        maxNesting = Math.max(maxNesting, currentNesting);
      } else if (char === '}' || char === ')' || char === ']') {
        currentNesting = Math.max(0, currentNesting - 1);
      }
    }
    
    return maxNesting;
  }

  /**
   * Extract imports from code
   */
  private extractImports(code: string, language: string): string[] {
    const imports: string[] = [];
    const lines = code.split('\n');
    
    for (const line of lines) {
      const trimmed = line.trim();
      
      // JavaScript/TypeScript/Dart/Java/Kotlin imports
      if (trimmed.startsWith('import ')) {
        imports.push(trimmed);
      }
      // Python from imports
      else if (trimmed.startsWith('from ')) {
        imports.push(trimmed);
      }
      // Rust use statements
      else if (trimmed.startsWith('use ')) {
        imports.push(trimmed);
      }
      // Go imports
      else if (trimmed.startsWith('import (') || trimmed.startsWith('import "')) {
        imports.push(trimmed);
      }
    }
    
    return imports.slice(0, 20); // Limit to 20 imports
  }

  /**
   * Extract basic components from code
   */
  private extractBasicComponents(code: string, language: string): ComponentAnalysis[] {
    const components: ComponentAnalysis[] = [];
    const lines = code.split('\n');
    
    const patterns: Record<string, RegExp[]> = {
      function: [
        /function\s+(\w+)/,
        /const\s+(\w+)\s*=\s*(?:async\s*)?\(/,
        /def\s+(\w+)/,
        /func\s+(\w+)/,
        /fn\s+(\w+)/,
      ],
      class: [
        /class\s+(\w+)/,
        /struct\s+(\w+)/,
      ],
      interface: [
        /interface\s+(\w+)/,
        /type\s+(\w+)\s*=/,
        /trait\s+(\w+)/,
      ],
    };
    
    for (let i = 0; i < lines.length && components.length < 15; i++) {
      const line = lines[i];
      
      for (const [type, regexes] of Object.entries(patterns)) {
        for (const regex of regexes) {
          const match = line.match(regex);
          if (match) {
            components.push({
              name: match[1],
              type: type as ComponentAnalysis['type'],
              description: `${type} defined at line ${i + 1}`,
              lineRange: { start: i + 1, end: i + 1 },
            });
            break;
          }
        }
      }
    }
    
    return components;
  }

  /**
   * Check if code has documentation
   */
  private hasDocumentation(code: string): boolean {
    return (
      code.includes('/**') ||
      code.includes('///') ||
      code.includes('"""') ||
      code.includes("'''") ||
      code.includes('# ') ||
      code.includes('//')
    );
  }

  /**
   * Check if code has error handling
   */
  private hasErrorHandling(code: string, language: string): boolean {
    const errorPatterns = [
      'try', 'catch', 'except', 'finally',
      'throw', 'raise', 'panic',
      'Result<', 'Option<', 'Either<',
      '.catch(', '.then(',
    ];
    
    return errorPatterns.some(pattern => code.includes(pattern));
  }
}

export const codeAnalysisService = new CodeAnalysisService();
export default codeAnalysisService;
