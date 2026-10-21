export interface FrameCatalogItem {
  readonly id: string;
  readonly name: string;
  readonly cost: number;
  readonly description: string;
  readonly order: number;
}

export const FRAME_CATALOG: readonly FrameCatalogItem[] = [
  { id: 'classic', name: 'Klasik', cost: 0, description: 'Sade ve şık orijinal kenarlık', order: 1 },
  { id: 'mint', name: 'Nane', cost: 100, description: 'Taze nane yeşili canlı çerçeve', order: 2 },
  { id: 'sunset', name: 'Gün Batımı', cost: 150, description: 'Sıcak gün batımı renkleri', order: 3 },
  { id: 'ocean', name: 'Okyanus', cost: 150, description: 'Derin mavi okyanus esintisi', order: 4 },
  { id: 'gold', name: 'Altın', cost: 300, description: 'Parıltılı şampiyon altını', order: 5 },
  { id: 'neon', name: 'Neon', cost: 300, description: 'Göz alıcı elektrik neonu', order: 6 },
  { id: 'rainbow', name: 'Gökkuşağı', cost: 500, description: 'Büyüleyici renk tayfı', order: 7 },
  { id: 'diamond', name: 'Elmas', cost: 800, description: 'Eşsiz kristal elmas ışıltısı', order: 8 },
];

export function isValidFrameId(id: string): boolean {
  return FRAME_CATALOG.some((item) => item.id === id);
}

export function getFrameCatalogItem(id: string): FrameCatalogItem | undefined {
  return FRAME_CATALOG.find((item) => item.id === id);
}

