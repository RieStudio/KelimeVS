export type FrameKind = 'procedural' | 'visual';
export type FrameTier = 'basic' | 'medium' | 'premium';

export const DEFAULT_VISUAL_FRAMES_MIN_BUILD = 11;

export interface FrameCatalogItem {
  readonly id: string;
  readonly name: string;
  readonly cost: number;
  readonly description: string;
  readonly order: number;
  readonly kind: FrameKind;
  readonly tier?: FrameTier;
  readonly minClientBuild?: number;
}

export const FRAME_CATALOG: readonly FrameCatalogItem[] = [
  { id: 'classic', name: 'Klasik', cost: 0, description: 'Sade ve şık orijinal kenarlık', order: 1, kind: 'procedural' },
  { id: 'mint', name: 'Nane', cost: 100, description: 'Taze nane yeşili canlı çerçeve', order: 2, kind: 'procedural' },
  { id: 'sunset', name: 'Gün Batımı', cost: 150, description: 'Sıcak gün batımı renkleri', order: 3, kind: 'procedural' },
  { id: 'ocean', name: 'Okyanus', cost: 150, description: 'Derin mavi okyanus esintisi', order: 4, kind: 'procedural' },
  { id: 'gold', name: 'Altın', cost: 300, description: 'Parıltılı şampiyon altını', order: 5, kind: 'procedural' },
  { id: 'neon', name: 'Neon', cost: 300, description: 'Göz alıcı elektrik neonu', order: 6, kind: 'procedural' },
  { id: 'rainbow', name: 'Gökkuşağı', cost: 500, description: 'Büyüleyici renk tayfı', order: 7, kind: 'procedural' },
  { id: 'diamond', name: 'Elmas', cost: 800, description: 'Eşsiz kristal elmas ışıltısı', order: 8, kind: 'procedural' },
  // Yeni Görsel (PNG) Çerçeveler (minClientBuild: 11)
  {
    id: 'bronze_engraved',
    name: 'Bronz Oyma',
    cost: 250,
    description: 'Özel oyma bronz sanatsal çerçeve',
    order: 9,
    kind: 'visual',
    tier: 'basic',
    minClientBuild: DEFAULT_VISUAL_FRAMES_MIN_BUILD,
  },
  {
    id: 'silver_engraved',
    name: 'Gümüş Oyma',
    cost: 400,
    description: 'Zarif gümüş oyma görsel çerçeve',
    order: 10,
    kind: 'visual',
    tier: 'basic',
    minClientBuild: DEFAULT_VISUAL_FRAMES_MIN_BUILD,
  },
  {
    id: 'gold_leaf',
    name: 'Altın Yaprak',
    cost: 600,
    description: 'Görkemli altın yaprak süslemeli çerçeve',
    order: 11,
    kind: 'visual',
    tier: 'medium',
    minClientBuild: DEFAULT_VISUAL_FRAMES_MIN_BUILD,
  },
  {
    id: 'vine',
    name: 'Sarmaşık',
    cost: 900,
    description: 'Doğal sarmaşık işlemeli prestijli çerçeve',
    order: 12,
    kind: 'visual',
    tier: 'premium',
    minClientBuild: DEFAULT_VISUAL_FRAMES_MIN_BUILD,
  },
];

export function isValidFrameId(id: string): boolean {
  return FRAME_CATALOG.some((item) => item.id === id);
}

export function getFrameCatalogItem(id: string): FrameCatalogItem | undefined {
  return FRAME_CATALOG.find((item) => item.id === id);
}

export function getMinClientBuildForFrame(
  item: FrameCatalogItem,
  env?: { VISUAL_FRAMES_MIN_BUILD?: string }
): number {
  if (item.kind === 'visual' && env?.VISUAL_FRAMES_MIN_BUILD) {
    const parsed = parseInt(env.VISUAL_FRAMES_MIN_BUILD, 10);
    if (Number.isFinite(parsed) && parsed >= 0) return parsed;
  }
  return item.minClientBuild ?? 0;
}

