import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  maskInappropriateText,
  maskSingleWord,
  isWordInappropriate,
} from '../src/engine/textMasker';
import {
  ALLOW_WORDS,
  EXACT_WORDS,
  CONTAINS_WORDS,
} from '../src/engine/nicknameBlocklist';

describe('TextMasker - Maç İçi Küfür Maskeleme', () => {
  describe('1. Tek Sözcük ve Temel Maskeleme Biçimi', () => {
    it('uygunsuz tekil sözcükleri ilk harf + yıldızlar biçiminde maskeler (uzunluk korunur)', () => {
      expect(maskInappropriateText('orospu')).toBe('o*****');
      expect(maskInappropriateText('sik')).toBe('s**');
      expect(maskInappropriateText('bok')).toBe('b**');
      expect(maskInappropriateText('pic')).toBe('p**');
      expect(maskInappropriateText('got')).toBe('g**');
    });

    it('tek karakterli uygunsuz girdi durumunda tek yıldız döner', () => {
      expect(maskSingleWord('')).toBe('');
      expect(maskSingleWord('a')).toBe('*');
      expect(maskSingleWord('s')).toBe('*');
    });

    it('boş, null veya string olmayan girdilerde güvenli çalışır', () => {
      expect(maskInappropriateText('')).toBe('');
      expect(maskInappropriateText(null as any)).toBe('');
      expect(maskInappropriateText(undefined as any)).toBe('');
    });
  });

  describe('2. Çok Sözcüklü Cümleler ve Orijinal Ayraçların Korunması', () => {
    it('yalnızca uygunsuz sözcükleri maskeler, masum sözcükleri ve boşlukları aynen korur', () => {
      expect(maskInappropriateText('sen bir orospusun')).toBe('sen bir o********');
      expect(maskInappropriateText('bu cok guzel bir oyun')).toBe('bu cok guzel bir oyun');
      expect(maskInappropriateText('tamam ben geliyorum')).toBe('tamam ben geliyorum');
    });

    it('noktalama işaretlerini ve ayraçları masum sözcüklerde korur', () => {
      expect(maskInappropriateText('ben, orospu değilim.')).toBe('ben, o***** değilim.');
      expect(maskInappropriateText('Merhaba! Nasılsın?')).toBe('Merhaba! Nasılsın?');
      expect(maskInappropriateText('Elma, armut, muz.')).toBe('Elma, armut, muz.');
    });

    it('sözcüğe bitişik noktalama ve rakamları maskeye dahil eder', () => {
      expect(maskInappropriateText('orospu123')).toBe('o********');
      expect(maskInappropriateText('sik99')).toBe('s****');
      expect(maskInappropriateText('orospu!')).toBe('o******');
    });
  });

  describe('3. Büyük/Küçük Harf ve Türkçe Karakter Duyarlılığı', () => {
    it('büyük ve küçük harf durumunu ilk harfte aynen korur', () => {
      expect(maskInappropriateText('Orospu')).toBe('O*****');
      expect(maskInappropriateText('OROSPU')).toBe('O*****');
      expect(maskInappropriateText('orospu')).toBe('o*****');
      expect(maskInappropriateText('SiK')).toBe('S**');
    });

    it('Türkçe karakterleri (Ş, İ, ı, ç, ö, ü, ğ) ilk harfte ve maskede doğru korur', () => {
      expect(maskInappropriateText('Şerefsiz')).toBe('Ş*******');
      expect(maskInappropriateText('şerefsiz')).toBe('ş*******');
      expect(maskInappropriateText('İbne')).toBe('İ***');
      expect(maskInappropriateText('ıbne')).toBe('ı***');
      expect(maskInappropriateText('piç')).toBe('p**');
      expect(maskInappropriateText('göt')).toBe('g**');
    });
  });

  describe('4. Leetspeak ve Kaçırma (Evasion) Girişimleri', () => {
    it('leetspeak ve sembol değişimlerini maskeler', () => {
      expect(maskInappropriateText('0r0spu')).toBe('0*****');
      expect(maskInappropriateText('p1c')).toBe('p**');
      expect(maskInappropriateText('p!c')).toBe('p**');
      expect(maskInappropriateText('s!k')).toBe('s**');
      expect(maskInappropriateText('5!k!5')).toBe('5****');
      expect(maskInappropriateText('51k15')).toBe('5****');
    });

    it('harfler arasına nokta, alt çizgi veya tire koyarak kaçma girişimlerini maskeler', () => {
      expect(maskInappropriateText('o.r.o.s.p.u')).toBe('o**********');
      expect(maskInappropriateText('o_r_o_s_p_u')).toBe('o**********');
      expect(maskInappropriateText('s_i_k')).toBe('s****');
      expect(maskInappropriateText('p.i.c')).toBe('p****');
    });

    it('art arda gelen tek harfli aralıklı yazımları (s i k gibi) tek aday olarak denetleyip aralığı maskeler', () => {
      expect(maskInappropriateText('s i k')).toBe('s****');
      expect(maskInappropriateText('s  i  k')).toBe('s******');
      expect(maskInappropriateText('o r o s p u')).toBe('o**********');
      expect(maskInappropriateText('sen s i k misin')).toBe('sen s**** misin');
      expect(maskInappropriateText('b o k yeme')).toBe('b**** yeme');
    });

    it('masum tek harfli kelimeleri (bağlaçları) yanlışlıkla maskelemez', () => {
      expect(maskInappropriateText('o ve a')).toBe('o ve a');
      expect(maskInappropriateText('a b c d e')).toBe('a b c d e');
    });
  });

  describe('5. Contains, Exact ve Allow Semantiği', () => {
    it('exact listesindeki kökler masum kelimelerin içinde maskelenmez', () => {
      // 'am', 'sik', 'got', 'bok', 'mal', '31' exact listesindedir
      expect(maskInappropriateText('damla')).toBe('damla');
      expect(maskInappropriateText('kamil')).toBe('kamil');
      expect(maskInappropriateText('amiral')).toBe('amiral');
      expect(maskInappropriateText('tamam')).toBe('tamam');
      expect(maskInappropriateText('fizik')).toBe('fizik');
      expect(maskInappropriateText('müzik')).toBe('müzik');
      expect(maskInappropriateText('boks')).toBe('boks');
      expect(maskInappropriateText('boksör')).toBe('boksör');
    });

    it('exact listesindeki kökler tek başınayken veya rakamla bitince maskelenir', () => {
      expect(maskInappropriateText('sik')).toBe('s**');
      expect(maskInappropriateText('sik99')).toBe('s****');
      expect(maskInappropriateText('mal')).toBe('m**');
      expect(maskInappropriateText('bok')).toBe('b**');
      expect(maskInappropriateText('pic123')).toBe('p*****');
    });

    it('sayısal ve trivia değerleri (31, 13, 1993, 3.1 vb.) maç içi maskelemeden muaftır', () => {
      expect(maskInappropriateText('31')).toBe('31');
      expect(maskInappropriateText('13')).toBe('13');
      expect(maskInappropriateText('1993')).toBe('1993');
      expect(maskInappropriateText('3.1')).toBe('3.1');
      expect(maskInappropriateText('3 1')).toBe('3 1');
      expect(maskInappropriateText('Apollo 13')).toBe('Apollo 13');
      expect(maskInappropriateText('Windows 3 1')).toBe('Windows 3 1');
      expect(maskInappropriateText('1923')).toBe('1923');
      expect(maskInappropriateText('10/10')).toBe('10/10');
      expect(maskInappropriateText('1923-1938')).toBe('1923-1938');
    });

    it('harf-rakam karışık leetspeak veya sonuna rakam eklenmiş küfürler maskelenmeye devam eder', () => {
      expect(maskInappropriateText('51k15')).toBe('5****');
      expect(maskInappropriateText('0r0spu')).toBe('0*****');
      expect(maskInappropriateText('p1c')).toBe('p**');
      expect(maskInappropriateText('p!c')).toBe('p**');
      expect(maskInappropriateText('s!k')).toBe('s**');
      expect(maskInappropriateText('sik99')).toBe('s****');
      expect(maskInappropriateText('orospu123')).toBe('o********');
    });

    it('contains listesindeki güçlü kökler ek aldığında da maskelenir', () => {
      expect(maskInappropriateText('orospular')).toBe('o********');
      expect(maskInappropriateText('sikerim')).toBe('s******');
      expect(maskInappropriateText('siktirgit')).toBe('s********');
      expect(maskInappropriateText('yarrak')).toBe('y*****');
    });

    it('allow listesindeki kelimeler maskelenmez', () => {
      expect(maskInappropriateText('kemal')).toBe('kemal');
      expect(maskInappropriateText('siklamen')).toBe('siklamen');
      expect(maskInappropriateText('kasik')).toBe('kasik');
      expect(maskInappropriateText('fistik')).toBe('fistik');
      expect(maskInappropriateText('lastik')).toBe('lastik');
      expect(maskInappropriateText('finnigan')).toBe('finnigan');
      expect(maskInappropriateText('3.1')).toBe('3.1');
    });
  });

  describe('6. SÖZLÜK PARİTE TESTİ (questions.json Tüm Cevaplar - 0 Yanlış Pozitif)', () => {
    it('server/src/dev/questions.json içindeki TÜM kabul edilen cevaplar maskeden geçince DEĞİŞMEZ', () => {
      const qPath = path.resolve(__dirname, '../src/dev/questions.json');
      const raw = JSON.parse(fs.readFileSync(qPath, 'utf8'));

      let count = 0;
      const falsePositives: Array<{ qId: string; original: string; masked: string }> = [];

      const pool = raw.questions_pool || {};
      for (const cat of Object.keys(pool)) {
        for (const qId of Object.keys(pool[cat])) {
          const q = pool[cat][qId];
          for (const [canonical, aliases] of Object.entries(q.acceptable_answers || {})) {
            const candidates = [canonical, ...(Array.isArray(aliases) ? aliases : [])];
            for (const cand of candidates) {
              count++;
              const masked = maskInappropriateText(cand);
              if (masked !== cand) {
                falsePositives.push({ qId, original: cand, masked });
              }
            }
          }
        }
      }

      expect(count).toBeGreaterThan(10000); // 11,853 cevap
      expect(falsePositives).toEqual([]);
    });

    it('app/assets/questions/questions.json içindeki TÜM kabul edilen cevaplar maskeden geçince DEĞİŞMEZ', () => {
      const appQPath = path.resolve(__dirname, '../../app/assets/questions/questions.json');
      const raw = JSON.parse(fs.readFileSync(appQPath, 'utf8'));

      let count = 0;
      const falsePositives: Array<{ qId: string; original: string; masked: string }> = [];

      const pool = raw.questions_pool || {};
      for (const cat of Object.keys(pool)) {
        for (const qId of Object.keys(pool[cat])) {
          const q = pool[cat][qId];
          for (const [canonical, aliases] of Object.entries(q.acceptable_answers || {})) {
            const candidates = [canonical, ...(Array.isArray(aliases) ? aliases : [])];
            for (const cand of candidates) {
              count++;
              const masked = maskInappropriateText(cand);
              if (masked !== cand) {
                falsePositives.push({ qId, original: cand, masked });
              }
            }
          }
        }
      }

      expect(count).toBeGreaterThan(10000);
      expect(falsePositives).toEqual([]);
    });
  });

  describe('7. Yanlış Pozitif Testi (200+ Türkçe İsim ve 100+ Oyun Takma Adı)', () => {
    const turkishNames = [
      'Ahmet', 'Mehmet', 'Ali', 'Ayşe', 'Fatma', 'Mustafa', 'Emine', 'Hatice', 'Hüseyin', 'Zeynep',
      'Can', 'Cem', 'Ece', 'Efe', 'Deniz', 'Derya', 'Gül', 'Elif', 'Burak', 'Bora',
      'Kemal', 'Cemal', 'Kamil', 'Damla', 'Samet', 'Muhammed', 'Muhammet', 'Murat', 'Orhan', 'Osman',
      'Yılmaz', 'Kaya', 'Demir', 'Çelik', 'Şahin', 'Yıldız', 'Yıldırım', 'Öztürk', 'Aydın', 'Özdemir',
      'Arslan', 'Doğan', 'Kılıç', 'Aslan', 'Çetin', 'Kara', 'Koç', 'Kurt', 'Özkan', 'Şimşek',
      'Polat', 'Korkmaz', 'Özer', 'Erdoğan', 'Yavuz', 'Aktaş', 'Yalçın', 'Güler', 'Güneş', 'Bozkurt',
      'Seda', 'Selin', 'Gizem', 'Burcu', 'Begüm', 'Beyza', 'Hande', 'Cansu', 'Dilara', 'Ceren',
      'Melis', 'Selen', 'İrem', 'Aslı', 'Başak', 'Burçin', 'Duygu', 'Ezgi', 'Fulya', 'Gözde',
      'Hilal', 'Ilgın', 'Işıl', 'Leman', 'Mine', 'Nalan', 'Nilgün', 'Nuray', 'Oya', 'Pınar',
      'Rana', 'Reyhan', 'Sanem', 'Şule', 'Yasemin', 'Zehra', 'Arda', 'Barış', 'Berk', 'Cemil',
      'Emre', 'Engin', 'Enes', 'Erdem', 'Eren', 'Fatih', 'Furkan', 'Gökhan', 'Hakan', 'Halil',
      'Hasan', 'İbrahim', 'İlker', 'Kaan', 'Kadir', 'Kenan', 'Kerem', 'Koray', 'Levent', 'Mahmut',
      'Ogün', 'Oğuz', 'Onur', 'Ömer', 'Rıza', 'Salih', 'Serdar', 'Serkan', 'Sinan', 'Şaban',
      'Şükrü', 'Taner', 'Tarık', 'Tolga', 'Tufan', 'Ufuk', 'Uğur', 'Umut', 'Vedat', 'Volkan',
      'Yağız', 'Yaman', 'Yiğit', 'Zafer', 'Alper', 'Batuhan', 'Berkay', 'Cenk', 'Doruk', 'Görkem',
      'Mert', 'Mete', 'Ozan', 'Rüzgar', 'Sarp', 'Taylan', 'Timur', 'Utku', 'Aylin', 'Banu',
      'Defne', 'Ebru', 'Filiz', 'Gülşen', 'Hale', 'Jale', 'Melek', 'Nehir', 'Özlem', 'Pelin',
      'Rüya', 'Sevil', 'Tülin', 'Ülkü', 'Adem', 'Bekir', 'Cihan', 'Davut', 'Ekrem', 'Feridun',
      'Galip', 'Hamza', 'İsmail', 'Lokman', 'Mansur', 'Necati', 'Orçun', 'Peyami', 'Rasim', 'Sedat',
      'Tahir', 'Ulaş', 'Vural', 'Yakup', 'Ziya', 'Adnan', 'Bülent', 'Cumhur', 'Dursun', 'Emin'
    ];

    it(`en az 200 yaygın Türkçe isim içerir (Mevcut: ${turkishNames.length}) ve hiçbiri maskelenmez`, () => {
      expect(turkishNames.length).toBeGreaterThanOrEqual(200);
      const maskedNames = turkishNames.filter((name) => maskInappropriateText(name) !== name);
      expect(maskedNames).toEqual([]);
    });

    const commonGameNicknames = [
      'Kral', 'Avci', 'Gezgin', 'Sampiyon', 'Usta', 'Kartal', 'Aslan', 'Kaplan', 'Ejderha', 'Firtina',
      'Ruzgar', 'Simsek', 'Golge', 'Pars', 'Bozkurt', 'DemirBilek', 'KelimeAvcisi', 'Bilge', 'Kaptan', 'Reis',
      'Efendi', 'Kahraman', 'Savasci', 'Muhafiz', 'SahinGoz', 'KeskinNisanci', 'SozUstasi', 'HizliCevap', 'Roket', 'Yildiz',
      'Gunes', 'Dolunay', 'Samanyolu', 'Evren', 'Gece', 'Safak', 'Aksam', 'Sabah', 'Bahar', 'Sonbahar',
      'Denizci', 'Dalgic', 'Pusula', 'Zirve', 'Dagci', 'Okcu', 'Buyucu', 'Sovalye', 'Barbar', 'Gladyator',
      'Samuray', 'Ninja', 'Viking', 'Korsan', 'Haydut', 'Casus', 'Ajan', 'Dedektif', 'Kasif', 'Yolcu',
      'Rehber', 'Oncu', 'Lider', 'Patron', 'Sef', 'Kralice', 'Prenses', 'Prens', 'Lord', 'Baron',
      'SahMat', 'Vezir', 'Kale', 'Piyon', 'Zafer', 'Basari', 'Enerji', 'Zeka', 'Akil', 'Fikir',
      'Kelimebaz', 'Sozluk', 'Bilgin', 'Dahi', 'Sihirbaz', 'AnkaKusu', 'AtesBilek', 'MaviGoz', 'KaraKus', 'AkilliOyuncu',
      'HizliKafa', 'UstaBeyin', 'SoruAvcisi', 'HarfKrali', 'HarfAvcisi', 'KelimeDahisi', 'KelimeLordu', 'MegaZeka', 'UltraBeyin', 'ProOyuncu'
    ];

    it(`en az 100 yaygın kelime/oyun adı içerir (Mevcut: ${commonGameNicknames.length}) ve hiçbiri maskelenmez`, () => {
      expect(commonGameNicknames.length).toBeGreaterThanOrEqual(100);
      const maskedNicks = commonGameNicknames.filter((nick) => maskInappropriateText(nick) !== nick);
      expect(maskedNicks).toEqual([]);
    });
  });

  describe('8. Performans ve Aşırı Uzun Metin Güvenliği', () => {
    it('tur başına 20 sözcüklü metin 1 ms altında işlenir (< 1 ms)', () => {
      const sentence =
        'Bu bir normal kelime oyunu turudur burada oyuncular yirmi adet kelime denerler ve orospu gibi kelimeler maskelenir tamam mı';

      // Warmup
      for (let i = 0; i < 50; i++) {
        maskInappropriateText(sentence);
      }

      const iterations = 500;
      const start = performance.now();
      for (let i = 0; i < iterations; i++) {
        maskInappropriateText(sentence);
      }
      const elapsedTotal = performance.now() - start;
      const avgMs = elapsedTotal / iterations;

      expect(avgMs).toBeLessThan(1.0); // 1 ms'nin çok altında
    });

    it('10.000 karakterlik aşırı uzun metinlerde güvenli ve hızlı çalışır', () => {
      const longText = 'kelime '.repeat(1500) + 'orospu ' + 'cevap '.repeat(500);
      const start = performance.now();
      const result = maskInappropriateText(longText);
      const duration = performance.now() - start;

      expect(result).toContain('o*****');
      expect(duration).toBeLessThan(50); // 50 ms altında
    });
  });
});
