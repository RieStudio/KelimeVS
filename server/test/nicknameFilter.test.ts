import { describe, expect, it } from 'vitest';
import {
  normalizeForFilter,
  isNicknameBlocked,
  parseWordList,
} from '../src/engine/nicknameFilter';
import {
  CONTAINS_WORDS,
  EXACT_WORDS,
  ALLOW_WORDS,
} from '../src/engine/nicknameBlocklist';

describe('NicknameFilter - Normalization & Engine Rules', () => {
  describe('1. Normalization (normalizeForFilter)', () => {
    it('Unicode NFKC normalizasyonunu uygular (ayrık veya birleşik karakterler)', () => {
      // Ayrık ş (\u0073\u0327) -> s
      expect(normalizeForFilter('\u0073\u0327')).toBe('s');
      // Fullwidth Latin harfler NFKC ile standart ASCII harfe dönüşür
      expect(normalizeForFilter('ＡＢＣ')).toBe('abc');
    });

    it('Türkçe farkındalıklı küçük harfe dönüştürür (İ, I, ı, i hepsi "i" olur)', () => {
      expect(normalizeForFilter('İ')).toBe('i');
      expect(normalizeForFilter('I')).toBe('i');
      expect(normalizeForFilter('ı')).toBe('i');
      expect(normalizeForFilter('i')).toBe('i');
      expect(normalizeForFilter('İpek')).toBe('ipek');
      expect(normalizeForFilter('IŞIK')).toBe('isik');
      expect(normalizeForFilter('ırmak')).toBe('irmak');
    });

    it('Türkçe karakterleri ve aksanları sadeleştirir (ş->s, ğ->g, ü->u, ö->o, ç->c, ı->i)', () => {
      expect(normalizeForFilter('şeker')).toBe('seker');
      expect(normalizeForFilter('ağaç')).toBe('agac');
      expect(normalizeForFilter('üzüm')).toBe('uzum');
      expect(normalizeForFilter('ördek')).toBe('ordek');
      expect(normalizeForFilter('çiçek')).toBe('cicek');
      expect(normalizeForFilter('kâğıt')).toBe('kagit');
    });

    it('Yaygın leetspeak ve sembolleri eşler (0->o, 1->i, 3->e, 4->a, 5->s, 7->t, 9->g, @->a, $->s, !->i, |->i, +->t)', () => {
      expect(normalizeForFilter('0')).toBe('o');
      expect(normalizeForFilter('1')).toBe('i');
      expect(normalizeForFilter('3')).toBe('e');
      expect(normalizeForFilter('4')).toBe('a');
      expect(normalizeForFilter('5')).toBe('s');
      expect(normalizeForFilter('7')).toBe('t');
      expect(normalizeForFilter('9')).toBe('g');
      expect(normalizeForFilter('@')).toBe('a');
      expect(normalizeForFilter('$')).toBe('s');
      expect(normalizeForFilter('!')).toBe('i');
      expect(normalizeForFilter('|')).toBe('i');
      expect(normalizeForFilter('+')).toBe('t');
      expect(normalizeForFilter('5!k!5')).toBe('sikis');
      expect(normalizeForFilter('0r0spu')).toBe('orospu');
      expect(normalizeForFilter('@pt@l')).toBe('aptal');
    });

    it('Ayraç ve görünmez karakterleri (boşluk, nokta, alt çizgi, tire, sıfır genişlikli) atar', () => {
      // Boşluk, nokta, tire, alt çizgi
      expect(normalizeForFilter('o.r_o-s p.u')).toBe('orospu');
      // Sıfır genişlikli karakterler (\u200B, \u200C, \u200D, \uFEFF)
      expect(normalizeForFilter('o\u200Br\u200Co\u200Ds\uFEFFpu')).toBe('orospu');
      expect(normalizeForFilter('s\u00ADi\u2060k')).toBe('sik');
    });

    it('Üst üste tekrarlanan harfleri teke indirir (aaa -> a, oo -> o)', () => {
      expect(normalizeForFilter('orooosspuuu')).toBe('orospu');
      expect(normalizeForFilter('aaaaaa')).toBe('a');
      expect(normalizeForFilter('ssiikkiiss')).toBe('sikis');
    });
  });

  describe('2. Kaçırma Denemelerinin Yakalanması (Evasion Attempts)', () => {
    it('Harfler arasına nokta, tire, alt çizgi veya boşluk koyarak kaçma girişimlerini engeller', () => {
      expect(isNicknameBlocked('o.r.o.s.p.u')).toBe(true);
      expect(isNicknameBlocked('o_r_o_s_p_u')).toBe(true);
      expect(isNicknameBlocked('o-r-o-s-p-u')).toBe(true);
      expect(isNicknameBlocked('o r o s p u')).toBe(true);
      expect(isNicknameBlocked('s.i.k.i.s')).toBe(true);
      expect(isNicknameBlocked('s_i_k_i_s')).toBe(true);
      expect(isNicknameBlocked('p.i.c')).toBe(true);
    });

    it('Leetspeak ve harf/rakam değişimlerini yakalar', () => {
      expect(isNicknameBlocked('0r0spu')).toBe(true);
      expect(isNicknameBlocked('s1k1s')).toBe(true);
      expect(isNicknameBlocked('51k15')).toBe(true);
      expect(isNicknameBlocked('s!k!s')).toBe(true);
      expect(isNicknameBlocked('p1c')).toBe(true);
      expect(isNicknameBlocked('p!c')).toBe(true);
      expect(isNicknameBlocked('@ptal')).toBe(true);
    });

    it('Harf uzatmalarını ve tekrarlarını yakalar', () => {
      expect(isNicknameBlocked('orooosspuuu')).toBe(true);
      expect(isNicknameBlocked('siiikkkiiisss')).toBe(true);
      expect(isNicknameBlocked('piiiççç')).toBe(true);
      expect(isNicknameBlocked('saalaak')).toBe(true);
    });

    it('Exact kelimelerde sondaki rakamları da yakalar', () => {
      expect(isNicknameBlocked('pic123')).toBe(true);
      expect(isNicknameBlocked('pic_99')).toBe(true);
      expect(isNicknameBlocked('got01')).toBe(true);
      expect(isNicknameBlocked('got_2026')).toBe(true);
      expect(isNicknameBlocked('bok_06')).toBe(true);
      expect(isNicknameBlocked('sik99')).toBe(true);
    });
  });

  describe('3. Contains / Exact / Allow Davranışları', () => {
    it('Contains listesindeki kelimeler cümlenin veya adın herhangi bir yerinde geçerse engellenir', () => {
      expect(isNicknameBlocked('BenOrospuyum')).toBe(true);
      expect(isNicknameBlocked('SikerimSeni')).toBe(true);
      expect(isNicknameBlocked('BirYavsak')).toBe(true);
    });

    it('Exact listesindeki kelimeler sadece tam eşleştiğinde engellenir, masum kelime içinde engellenmez', () => {
      // Exact kelime tek başına veya sonuna rakamla engellenir
      expect(isNicknameBlocked('am')).toBe(true);
      expect(isNicknameBlocked('a_m')).toBe(true);
      expect(isNicknameBlocked('am_99')).toBe(true);
      expect(isNicknameBlocked('sik')).toBe(true);
      expect(isNicknameBlocked('mal')).toBe(true);
      expect(isNicknameBlocked('bok')).toBe(true);

      // Ancak masum kelimelerin içinde geçince ENGELLEYEMEZ (false positive olmaz)
      expect(isNicknameBlocked('Damla')).toBe(false);
      expect(isNicknameBlocked('Kamil')).toBe(false);
      expect(isNicknameBlocked('Samet')).toBe(false);
      expect(isNicknameBlocked('Amiral')).toBe(false);
      expect(isNicknameBlocked('Kemal')).toBe(false);
      expect(isNicknameBlocked('Cemal')).toBe(false);
      expect(isNicknameBlocked('Boksör')).toBe(false);
    });

    it('Allow listesindeki kelimeler maskelenir ve yanlış pozitif üretmez', () => {
      expect(isNicknameBlocked('Siklamen')).toBe(false);
      expect(isNicknameBlocked('Fıstık')).toBe(false);
      expect(isNicknameBlocked('Kaşık')).toBe(false);
      expect(isNicknameBlocked('Klasik')).toBe(false);
      expect(isNicknameBlocked('Sarımsak')).toBe(false);
      expect(isNicknameBlocked('Eksik')).toBe(false);
      expect(isNicknameBlocked('Fizik')).toBe(false);
      expect(isNicknameBlocked('Müzik')).toBe(false);
      expect(isNicknameBlocked('Lastik')).toBe(false);
    });

    it('Allow kelimesi yanında gerçek küfür varsa yakalanmaya devam eder', () => {
      expect(isNicknameBlocked('FıstıkSikiş')).toBe(true);
      expect(isNicknameBlocked('KaşıkOrospu')).toBe(true);
    });
  });

  describe('4. Liste Parser Güvenliği (parseWordList)', () => {
    it('Boş satırları ve # ile başlayan yorum satırlarını güvenle yok sayar', () => {
      const input = `
        # Bu bir yorumdur
        kelime1
        # Başka bir yorum
        
        kelime2
      `;
      const result = parseWordList(input);
      expect(result).toEqual(['kelime1', 'kelime2']);
    });

    it('Boş liste verilirse hata fırlatmaz, güvenli çalışır', () => {
      expect(isNicknameBlocked('Ahmet', { contains: [], exact: [], allow: [] })).toBe(false);
      expect(isNicknameBlocked('kufur', { contains: [], exact: [], allow: [] })).toBe(false);
    });
  });

  describe('5. Yanlış Pozitif Testi (En az 200 Türkçe İsim/Soyisim ve 100 Oyun Adı)', () => {
    const turkishFirstNames = [
      'Ahmet', 'Mehmet', 'Mustafa', 'Ali', 'Can', 'Cem', 'Zeynep', 'Ayşe', 'Fatma', 'Emine',
      'Hatice', 'Elif', 'Merve', 'Büşra', 'Tuğba', 'Kübra', 'Gamze', 'Seda', 'Selin', 'Gizem',
      'Derya', 'Deniz', 'Burcu', 'Begüm', 'Beyza', 'Hande', 'Cansu', 'Damla', 'Dilara', 'Ceren',
      'Melis', 'Selen', 'Ece', 'İrem', 'Aslı', 'Başak', 'Burçin', 'Duygu', 'Ezgi', 'Fulya',
      'Gözde', 'Hilal', 'Ilgın', 'Işıl', 'Leman', 'Mine', 'Nalan', 'Nilgün', 'Nuray', 'Oya',
      'Pınar', 'Rana', 'Reyhan', 'Sanem', 'Şule', 'Yasemin', 'Zehra', 'Arda', 'Barış', 'Berk',
      'Bora', 'Burak', 'Cemil', 'Doğan', 'Emre', 'Engin', 'Enes', 'Erdem', 'Eren', 'Fatih',
      'Furkan', 'Gökhan', 'Hakan', 'Halil', 'Hasan', 'Hüseyin', 'İbrahim', 'İlker', 'Kaan', 'Kadir',
      'Kemal', 'Kenan', 'Kerem', 'Koray', 'Levent', 'Mahmut', 'Murat', 'Ogün', 'Oğuz', 'Onur',
      'Orhan', 'Osman', 'Ömer', 'Rıza', 'Salih', 'Samet', 'Serdar', 'Serkan', 'Sinan', 'Şaban',
      'Şahin', 'Şükrü', 'Taner', 'Tarık', 'Tolga', 'Tufan', 'Ufuk', 'Uğur', 'Umut', 'Vedat',
      'Volkan', 'Yağız', 'Yaman', 'Yiğit', 'Zafer', 'Alper', 'Batuhan', 'Berkay', 'Cenk', 'Doruk',
      'Efe', 'Görkem', 'Mert', 'Mete', 'Ozan', 'Polat', 'Rüzgar', 'Sarp', 'Taylan', 'Timur',
      'Utku', 'Yalçın', 'Yavuz', 'Aylin', 'Banu', 'Defne', 'Ebru', 'Filiz', 'Gülşen', 'Hale',
      'Jale', 'Melek', 'Nehir', 'Özlem', 'Pelin', 'Rüya', 'Sevil', 'Tülin', 'Ülkü', 'Yıldız',
      'Adem', 'Bekir', 'Cihan', 'Davut', 'Ekrem', 'Feridun', 'Galip', 'Hamza', 'İsmail', 'Kamil',
      'Lokman', 'Mansur', 'Necati', 'Orçun', 'Peyami', 'Rasim', 'Sedat', 'Tahir', 'Ulaş', 'Vural',
      'Yakup', 'Ziya', 'Adnan', 'Bülent', 'Cumhur', 'Dursun', 'Emin', 'Faruk', 'Gani', 'Hayati'
    ];

    const turkishLastNames = [
      'Yılmaz', 'Kaya', 'Demir', 'Çelik', 'Şahin', 'Yıldız', 'Yıldırım', 'Öztürk', 'Aydın', 'Özdemir',
      'Arslan', 'Doğan', 'Kılıç', 'Aslan', 'Çetin', 'Kara', 'Koç', 'Kurt', 'Özkan', 'Şimşek',
      'Polat', 'Korkmaz', 'Özer', 'Erdoğan', 'Yavuz', 'Aktaş', 'Yalçın', 'Güler', 'Güneş', 'Bozkurt',
      'Bulut', 'Keskin', 'Ünal', 'Kaplan', 'Tunç', 'Avcı', 'Coşkun', 'Duman', 'Acar', 'Yiğit'
    ];

    // Toplam 170 ad + 40 soyad = 210 yaygın Türkçe isim/soyisim
    const allTurkishNames = [...turkishFirstNames, ...turkishLastNames];

    it(`en az 200 yaygın Türkçe ad/soyad içerir (Mevcut: ${allTurkishNames.length}) ve hepsi KABUL EDİLİR`, () => {
      expect(allTurkishNames.length).toBeGreaterThanOrEqual(200);

      const falsePositives: string[] = [];
      for (const name of allTurkishNames) {
        if (isNicknameBlocked(name)) {
          falsePositives.push(name);
        }
      }
      expect(falsePositives).toEqual([]);
    });

    const commonGamingNicknames = [
      'Kral', 'Avci', 'Gezgin', 'Sampiyon', 'Usta', 'Kartal', 'Aslan', 'Kaplan', 'Ejderha', 'Firtina',
      'Ruzgar', 'Simsek', 'Golge', 'Pars', 'Bozkurt', 'DemirBilek', 'KelimeAvcisi', 'Bilge', 'Kaptan', 'Reis',
      'Efendi', 'Kahraman', 'Savasci', 'Muhafiz', 'SahinGoz', 'KeskinNisanci', 'SozUstasi', 'HizliCevap', 'Roket', 'Yildiz',
      'Gunes', 'Dolunay', 'Samanyolu', 'Evren', 'Gece', 'Safak', 'Aksam', 'Sabah', 'Bahar', 'Sonbahar',
      'Denizci', 'Dalgic', 'Pusula', 'Zirve', 'Dagci', 'Okcu', 'Buyucu', 'Sovalye', 'Barbar', 'Gladyator',
      'Samuray', 'Ninja', 'Viking', 'Korsan', 'Haydut', 'Casus', 'Ajan', 'Dedektif', 'Kasif', 'Yolcu',
      'Rehber', 'Oncu', 'Lider', 'Patron', 'Sef', 'Kralice', 'Prenses', 'Prens', 'Lord', 'Baron',
      'SahMat', 'Vezir', 'Kale', 'Piyon', 'Zafer', 'Basari', 'Enerji', 'Zeka', 'Akil', 'Fikir',
      'Kelimebaz', 'Sozluk', 'Bilgin', 'Dahi', 'Sihirbaz', 'AnkaKusu', 'AtesBilek', 'MaviGoz', 'KaraKus', 'AkilliOyuncu',
      'HizliKafa', 'UstaBeyin', 'SoruAvcisi', 'HarfKrali', 'HarfAvcisi', 'KelimeDahisi', 'KelimeLordu', 'MegaZeka', 'UltraBeyin', 'ProOyuncu',
      'MasterGamer', 'StarPlayer', 'ApexWarrior', 'CyberGhost', 'IronHeart', 'ShadowHunter', 'FalconEye', 'StormBringer', 'SilverArrow', 'GoldenKnight'
    ];

    it(`en az 100 yaygın kelime/oyun takma adı içerir (Mevcut: ${commonGamingNicknames.length}) ve hepsi KABUL EDİLİR`, () => {
      expect(commonGamingNicknames.length).toBeGreaterThanOrEqual(100);

      const falsePositives: string[] = [];
      for (const nick of commonGamingNicknames) {
        if (isNicknameBlocked(nick)) {
          falsePositives.push(nick);
        }
      }
      expect(falsePositives).toEqual([]);
    });

    it('Rakamlı ve alt çizgili yaygın takma adlar serbestçe KABUL EDİLİR', () => {
      const numberedNicknames = [
        'Ahmet_99', 'Zeynep_06', 'Mehmet34', 'Can_Pro_1', 'Elif2024',
        'Kral_2026', 'Usta_12', 'Kartal_1903', 'Aslan_1905', 'Kanarya_1907',
        'Kelime_01', 'Gamer_99', 'Pro_2025', 'Star_77', 'Demir_42'
      ];

      for (const nick of numberedNicknames) {
        expect(isNicknameBlocked(nick)).toBe(false);
      }
    });
  });
});
