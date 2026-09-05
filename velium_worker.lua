#!/usr/bin/env lua
-- ============================================================
-- VELIUM WORKER  v4.2  (Termux, Redfinger)
-- 1 WORKER = 1 TIM = 1 RedFinger = 6-10 client Roblox.
--
-- Beda dari v3.0 (ntfy) -> v4.0 (Cloudflare Worker):
--   * ntfy DIBUANG. Satu layanan, satu kunci, satu alamat.
--   * Perintah : GET  /perintah?tim=X   (dulu: ntfy.sh/topic/json?poll=1)
--   * Status   : POST /tim              (dulu: ntfy.sh/topic-status)
--   * Kunci beneran (X-Kunci). Topic ntfy itu publik â€” siapa pun yang tau
--     namanya bisa nembak FORCE ke tim lo.
--   * CPU/RAM jadi keluar di panel.
--
-- v4.1: * Paket Roblox DIPINDAI OTOMATIS dari device. Gak usah ngetik
--         6-10 nama paket satu-satu (gampang typo, susah dicek).
--       * win_mode: OPSIONAL, bawaan 0 = jangan disenggol. Client yang
--         udah auto-freeform gak perlu ini.
--       * BUKA BERGILIR + DIVERIFIKASI. Tiap client ditungguin sampai
--         beneran jalan sebelum lanjut ke berikutnya. Gagal -> diulang,
--         terus dilaporin nama paketnya. Gak lagi tembak-lari.
--
-- v4.2: BISA DIMATIIN. Dulu cuma bisa `pkill` â€” mati mendadak, notif
--       nyangkut, wake-lock kepegang, panel gak tau.
--         lua5.4 velium_worker.lua stop     -> berhenti baik-baik
--         lua5.4 velium_worker.lua status   -> jalan apa nggak
--         KILL dari panel                 -> worker mati (beda dari STANDBY)
--       Plus: gak bisa dobel jalan (2 worker 1 tim = RAM jebol).
--
-- Perintah nempel (sticky) sampai diganti. Di ntfy dulu perlu akal-akalan
-- forceSticky karena pesan kedaluwarsa. Sekarang perintahnya kesimpen di DB,
-- jadi isinya = keadaannya. Lebih simpel & gak bisa "ilang" sendiri.
--
-- v4.17: MASUK GAME DIKONFIRMASI BRIDGE (bukan cuma "proses muncul").
--        Masalah: halaman Home Roblox JUGA pakai ActivityNativeMain, jadi
--        client yg nyangkut di Home (kena popup age-check / PS link gagal)
--        ke-baca "jalan" -> worker lanjut ke client lain, gak ngulang.
--        Fix: setelah proses muncul, worker TUNGGUIN akun lapor BARU ke
--        /stat (sinyal sama kayak auto-rejoin). Lapor baru = script jalan =
--        BENERAN di game. Bridge diem sampai timeout = nyangkut -> ulang buka.
--        Skip "udah jalan" juga dicek bridge, biar Home-stuck gak ke-skip.
--        Default delay dinaikin (stagger 15, tunggu 60) + konfirmasi_sec 90.
--
-- v4.18: ORIENTASI LAYAR + KEEP-ALIVE (anti-FC).
--        * orientasi: kunci RF ke landscape/portrait (opsional, setup).
--        * keep-alive: client Roblox tahan di background (deviceidle whitelist +
--          appops RUN_IN_BACKGROUND + oom_score_adj rendah, di-apply ulang tiap
--          menit karena Android suka reset). Worker DILINDUNGIN LEBIH KUAT dari
--          client -> kalau RAM mentok, yg dikorbanin client (bisa rejoin), bukan
--          worker. CATATAN: di device RAM sesek keep-alive NGURANGIN kill, bukan
--          NGILANGIN -> tetep bisa reboot kalau kepepet. Jaring rejoin tetep jalan.
--
-- v4.19: REJOIN GANTI SERVER: CEPET + NYEROBOT.
--        * REJOIN (dari panel, ganti PS) pakai FAST mode -> skip bridge-confirm
--          (gak nunggu tiap client lapor 90s). alur tetep: tutup semua -> refresh
--          assign-ps (nurut panel) -> buka lagi ke PS baru, tapi CEPET.
--        * REJOIN/CLOSE NYEROBOT FORCE yg lagi jalan -> FORCE dibatalin, perintah
--          panel langsung dikerjain (gak nyangkut nunggu FORCE kelar dulu).
--        FORCE/reopen berkala TETEP pakai bridge-confirm (biar Home-stuck ketangkep).
--
-- v4.20: REJOIN PER-CLIENT bisa BANYAK akun sekaligus.
--        REJOIN:akun1,akun2 -> rejoin per-client masing-masing (tutup 1 buka 1),
--        JANGAN kill all. Buat panel: kalau ganti server cuma sebagian client,
--        yg di-rejoin cuma yg berubah (per-client). Kill all CUMA kalau REJOIN
--        polos (tanpa :akun) = ganti server SEMUA client sekaligus.
--
-- v4.21: FALSE-OFF FIX (client kebekuin Android, keliatan off padahal di server).
--        * MATIIN cached-app freezer (settings + device_config) -> Roblox background
--          gak dibekuin -> loop script tetep jalan -> tetep lapor -> gak dikira off.
--        * wake-lock CPU pas start (worker + client gak ditidurin layar idle).
--        * AUTO-REJOIN pinter: bridge diem TAPI client masih di game (pkg_running) ->
--          cukup DIBANGUNIN (bawa ke depan), JANGAN kill+buka. kill cuma kalau
--          beneran keluar dari layar game.
--
-- v4.22: freezer-disable DICABUT (teorinya salah -- game jalan normal, yg berhenti
--        cuma LAPORAN bridge). akar masalahnya jarak denyut kekencengan vs ambang
--        off panel; dibenerin di script: star_farm v13.10 (denyut 300->120) +
--        market v8.336 (gagal kirim gak lagi dianggap sukses). nudge auto-rejoin
--        (v4.21) TETEP dipake -- itu tetep bener biar client idup gak di-kill.
--
-- v4.23: PINDAH SERVER OTOMATIS (buat suplai pet market <- leveling).
--        * PS berubah di panel/CF -> worker rejoin client itu DOANG ke PS baru.
--          Ini mesin umum: siapa pun yg ubah assign-ps, client nyusul sendiri.
--        * suplai_master (v4.28: OTOMATIS tim-1, gak ditanya lagi) manggil /suplai-cek
--          tiap 60 detik -> CF ngumpulin akun market yg stok nipis ke PS akun
--          leveling yg pet siap-gift-nya banyak, terus mulangin kalau udah cukup.
--          Cuma tim-1 -> mustahil rebutan nulis (dulu bisa bikin akun gak balik).
--
-- v5.25: `velium cookie` -- ekstrak cookie .ROBLOSECURITY dari akun sendiri buat
--        BACKUP / pindah device. Bukan bypass apa-apa -- cuma baca kredensial
--        milik sendiri dari storage client yang lagi login.
--          velium cookie          -> cuma client yang LAGI JALAN (yg terkait)
--          velium cookie <huruf>  -> satu client (com.roblox.clien<huruf>)
--          velium cookie all      -> semua paket kepasang (jalan atau nggak)
--        "Bukti dulu": lokasi & format simpan cookie di clone App Cloner belum
--        pasti, jadi command ini NAMPILIN file mana yg punya ROBLOSECURITY +
--        ekstrak nilainya. Kalau nihil -> lokasinya beda, kabarin biar disetel.
--        Pakai timeout panjang (grep rekursif lama) -- bukan sh() yg dipatok 8s.
--
-- v5.26: `velium cookie` sekarang ngasih LABEL NAMA AKUN (baca_username dari
--        prefs.xml, sumber yg sama kayak mapping client<->akun auto-rejoin).
--        Format file jadi: <akun>\t<paket>\t<cookie>. Gampang dicocokin pas
--        restore. Akun '?' = prefs.xml belum punya username (client baru).
--
-- v5.27: `velium cookie` sekarang AUTO-KIRIM cookie ke panel (CF /cookie-simpan)
--        selain nulis file lokal. Di panel digerbang password (tab Cookie),
--        sesi 24 jam. File /sdcard tetep ditulis sebagai cadangan. Butuh:
--        tabel D1 'cookies' + endpoint /cookie-* di TEMPEL-KE-CLOUDFLARE.js.
--
-- v5.28: `velium verif` -- daftar client yang BUTUH DICEK MANUAL. Bukan deteksi
--        captcha (mustahil di RF ini -- layar kebaca 0 teks, lihat 5.9/v4.85),
--        tapi penyaring POLA: idup tapi bridge gak pernah lapor = nyangkut
--        sebelum masuk game (verif bot / layar key / popup umur semuanya masuk
--        pola ini). Sekali dumpsys + sekali su + sekali GET /stat. Keputusan
--        (ganti akun / verif manual) tetap di user -- worker gak nyentuh apa2.
--
-- v5.29: SCRIPT PER TIM DARI PANEL. Dulu tiap RF nulis `velium_loader.lua` dari
--        cfg.script_url LOKAL -- ganti script = edit config di tiap RF satu-satu.
--        Sekarang panel bisa nentuin tim ini jalanin script apa; URL-nya nebeng
--        di respons /perintah (yang emang udah di-poll), jadi NOL request tambahan.
--        Begitu ganti: autoexec ditulis ulang + semua client ditutup (Delta cuma
--        baca Autoexecute pas masuk game, jadi yang lagi jalan masih pakai script
--        lama). Yang buka lagi blok FORCE. Kalau panel gak nentuin apa-apa,
--        jatuh balik ke cfg.script_url lokal -- perilaku lama tetep jalan.
--
-- v5.30: LAPORAN KE PANEL YANG GAGAL SEKARANG KELIATAN.
--        Dulu `api_post(cfg, "/tim", body)` nilai baliknya DIBUANG. Kalau POST
--        ditolak (kunci salah, backend belum deploy, tim kosong), worker tetep
--        keliatan normal -- config kebaca, tim kedeteksi, polling jalan --
--        sementara di panel timnya KOSONG. Gagalnya diem, susah dilacak.
--        Sekarang: baris status di layar ("LAPOR KE PANEL GAGAL: <sebab>")
--        + perintah `velium panel` yang nguji tiap endpoint satu-satu.
--        Catatan kenapa gejalanya menyesatkan: GET /perintah bisa LOLOS
--        sementara POST /tim ditolak -- dua-duanya endpoint beda.
--
-- v5.31: KUNCI API bypass.vip GAK DITANYA LAGI pas setup. Diisi SEKALI di
--        panel, semua RF narik dari /bypass-key. Dulu ditanyain tiap setup --
--        20 RF = 20 kali ngetik kunci yang sama, dan sekali salah ketik
--        `velium key` gagal tanpa sebab yang jelas.
--        Urutan: config lokal MENANG (kalau RF ini perlu kunci beda), baru
--        panel. Hasil panel di-cache 10 menit; kalau panel mati, yang udah
--        kepegang tetep kepakai.
--        Tetep GAK masuk GitHub -- kuncinya di D1, bukan di berkas yang
--        di-push.
--
-- v5.32: kunci API DITARIK PAS WORKER NYALA, terus DISIMPEN ke config lokal.
--        Sekali narik, habis itu instan & gak butuh panel lagi. Ini penting
--        karena `velium key` dipanggil justru pas lisensi Delta abis -- saat
--        paling genting; kalau baru narik di situ dan panel lagi mati,
--        bypass-nya gagal.
--        Hasilnya: gak perlu ngetik manual di tiap RF, TANPA harus naruh
--        kunci di berkas yang di-push ke GitHub.
--
-- v5.33: kunci API DITARUH LANGSUNG di file ini (BYPASS_KEY_BAWAAN), atas
--        permintaan user -- repo `revsy` PRIVAT. Nol delay, gak nanya panel
--        sama sekali. Urutan: config lokal > bawaan > panel.
--        !! KALAU REPO DIJADIIN PUBLIK, KOSONGIN BYPASS_KEY_BAWAAN DULUAN !!
--        Itu kunci langganan berbayar -- siapa pun yang bisa baca file ini
--        bisa ngabisin kuotanya.
--
-- v5.34: nama akun di tabel dipotong dari DEPAN, bukan belakang. Nama akun
--        polanya awalan+nomor (wildnx_12, oliviainvent3) -- yang MEMBEDAKAN
--        ada di ujung belakang. Motong dari belakang bikin 4 akun beda
--        keliatan sama persis, dan itu nyesatin: keliatannya kayak 4 client
--        login ke satu akun yang sama. Kolomnya juga dilebarin 12 -> 14.
--
-- v5.35: SCRIPT AUTOEXEC DIPILIH SENDIRI pas setup: STAR FARM / STAR SEED /
--        MARKET. Dulu kepaksa ngikut game -- GAG 2 selalu dapet `gag2`.
--        Padahal satu tim GAG 2 bisa dipakai buat dua hal beda: farm kebun
--        atau AFK beli seed. Bawaannya nyesuain game, jadi kasus umum
--        tinggal Enter.
--
-- v5.36: pertanyaan "Folder autoexec" DIBUANG dari setup. Jawabannya selalu
--        sama -- 20 RF = 20 kali mencet Enter buat nilai yang gak pernah beda.
--        Nilainya tetep ketulis di config, dan ada cadangan di dua tempat
--        (run + tulis_autoexec), jadi gak ada yang rusak. Kalau suatu saat
--        ada RF yang foldernya beda: edit config -> autoexec_dir="/path/lain"
--
-- v5.37: pertanyaan "Pakai shell root tetap?" DIBUANG, bawaannya jadi NYALA.
--        Dulu bawaannya "n" padahal selalu dijawab y -- dan untungnya besar
--        (tiap 'su' di RF makan ~6 detik, ini bikin root dibuka sekali aja).
--        Aman dipaksa: dites pas nyala, gagal = balik ke cara lama; kalau
--        shell-nya mati di tengah jalan juga kedeteksi. Paling jelek dia cuma
--        balik ke perilaku lama.
--        Config lama yang shell_tetap=false tetep dihormatin.
--
-- v5.38: pertanyaan "Auto grid?" DIBUANG, bawaannya NYALA. Grid itu bukan
--        pilihan gaya -- jendela HARUS ketata biar URL key Delta bisa diambil
--        dari tiap client. Susunannya juga udah otomatis dari dulu:
--        grid_hitung baca ukuran layar sendiri + tabel SUSUNAN (4 client ->
--        2x2). Sekarang hasil hitungannya ditampilin pas setup, biar keliatan
--        gak ada yang perlu diatur.
--
-- v5.39: SETUP NYETEL PERINTAH AWAL SENDIRI = FORCE.
--        Dulu RF yang baru selesai setup NGANGGUR: "perintah: -", semua client
--        off, gak ada yang jalan sampai ada orang mencet "Jalankan semua" di
--        panel. Gejalanya nyesatin -- worker keliatan sehat (nyambung, lapor
--        jalan tiap detik) tapi gak ngapa-ngapain, dan gak ada petunjuk kenapa.
--        Padahal RF yang baru disetup ya jelas mau dijalanin.
--        Mau ditahan dulu? panel -> "Hentikan".
--        Sekalian api_post bisa milih metode (bawaan POST) -- /perintah minta
--        PUT, dan tanpa itu setup gak bisa nyetel perintahnya sendiri.
--
-- v5.40: FIX `up` nyangkut di versi lama. Kejadian nyata: `up` di RF bilang
--        "OK 5.35" berulang-ulang padahal GitHub udah 5.39 -- dan karena dia
--        bilang OK (bukan gagal), gak ada yang curiga.
--        Sebabnya: `up` itu skrip yang dibikin SEKALI pas `pasang`. RF yang
--        dipasang pakai worker lama kebawa skrip lama selamanya.
--        Sekarang worker NULIS ULANG `up` tiap nyala (cuma kalau isinya beda),
--        jadi sekali dapet worker baru, `up`-nya kebetulin sendiri.
--        Plus: header no-cache (jaga-jaga ada proxy di jaringan RF yang gak
--        peduli sama ?t=), dan alamat repo disatuin jadi SATU konstanta --
--        dulu ketulis di dua tempat, bisa beda diam-diam.
--
-- v5.41: FILE LAIN di folder autoexec DIBUANG pas nulis loader.
--        Delta jalanin SEMUA file di folder itu. Jadi sisa script lama
--        (text.txt yang pernah ditaruh manual, loader dari nama lama) bakal
--        jalan BARENGAN sama yang baru -- dua script aktif di satu client,
--        aksi dobel, atau yang bener ketimpa yang salah.
--        Yang dilewat cuma velium_loader.txt punya kita. Apa aja yang dibuang
--        DILAPORIN, biar gak ada yang ilang diam-diam.
--        Digabung ke panggilan su yang sama -> praktis gratis.
--        Mau dimatiin: config -> autoexec_bersih=false
--
-- v5.42: `velium panel` diperluas -- sekarang ikut ngecek AKUN, bukan cuma
--        sambungan. Perlu karena ada gejala yang gak kejelasan sebabnya:
--        panel bilang "0 akun di tim ini" padahal client-nya ada dan worker
--        nampilin nama akunnya di tabel.
--        Tiga langkah baru:
--          5. akun yang worker TAU (dari prefs.xml tiap client)
--          6. POST /assign-tim + jawaban mentahnya
--          7. cek di /stat: akun itu kecatat di tim & game APA
--        Langkah 7 yang menentukan: akun cuma nongol di sebuah tab kalau
--        tim DAN game-nya cocok. Kalau game-nya kebawa dari pemakaian lama
--        (mis. akun ini dulu dipakai GAG 1), dia gak akan nongol di tab GAG 2
--        walau timnya bener.
--
-- v5.43: auto-assign sekarang LAPOR apa yang dibetulin, bukan cuma jumlahnya.
--        Pasangannya perubahan di CF (/assign-tim v15-66): kolom `game` DITIMPA
--        dari worker, dan `place` yang nunjuk game lain DIBUANG.
--        Kenapa dua-duanya: panel nentuin game akun dari PLACE[place] DULU,
--        baru kolom game. Jadi betulin `game` aja gak cukup -- place basi
--        masih nutupin, dan akunnya tetep nyangkut di tab game lama.
--        Yang TETEP dijaga: akun milik tim LAIN gak direbut.
--
-- v5.44: PEMBALIKAN dari v5.43 -- worker pemegang client SEKARANG MEREBUT akun
--        dari tim lain, dan perpindahannya dilaporin.
--        Kenapa dibalik: bukti lapangan (velium panel) nunjukin 4 akun nyangkut
--        di tim-1/GAG 1 MARKET sisa pemakaian lama, padahal fisiknya udah di
--        RF tim-4. Perlindungan v5.43 ("jangan rebut") justru yang ngeblok --
--        gameDiperbarui=0, dan akunnya nyangkut SELAMANYA tanpa sebab yang
--        keliatan.
--        Dasarnya: worker baca nama akun dari prefs.xml client-nya SENDIRI.
--        Itu bukan rencana, itu FAKTA. Kalau kolom tim di panel bilang lain,
--        yang basi itu panelnya.
--        Risiko tarik-menarik (akun kepasang di 2 RF) sekarang KEKIHATAN --
--        tiap perebutan dilaporin, jadi kalau muncul terus buat akun yang
--        sama, ketara.
--
-- v5.45: status "off" DIPECAH jadi "off" dan "latar".
--        Sebabnya pertanyaan yang wajar: log bilang "tutup paksa" buat client
--        yang di tabel keliatan "off" -- kesannya gak masuk akal.
--        Ternyata ada DUA ukuran beda:
--          tabel      -> dumpsys: ada JENDELA di layar?
--          saat buka  -> pidof:   PROSESnya idup?
--        Client bisa prosesnya idup tapi jendelanya gak ada (jalan di latar).
--        Keadaan itu HARUS ditutup dulu -- 'am start' ke proses yang masih
--        idup itu NO-OP, dia nangkring di server lama.
--        Jadi perilakunya bener, cuma labelnya nyesatin. Sekarang:
--          â—‹ off   = mati total, tinggal dibuka
--          â— latar = proses idup tanpa jendela -> bakal ditutup dulu
--        pidof digabung ke panggilan su yang SAMA -> nol ongkos tambahan.
--
-- v5.46: LISENSI DELTA DICEK DULU, sebelum buka semua client.
--        Dulu bypass jalan di loop utama -- artinya SETELAH semua client
--        kebuka. Akibatnya keempat client nyangkut bareng di layar
--        "Enter key", makan RAM & CPU percuma, baru dibypass belakangan.
--        Berkas lisensinya di /sdcard, dipakai BARENG semua client (verif
--        Delta itu per-DEVICE, bukan per-instance). Jadi urutan yang bener:
--          1. cek lisensi
--          2. hilang/basi -> buka SATU client, bypass, tulis kunci
--          3. baru buka sisanya -- semuanya langsung lolos ke game
--        Kalau auto_key MATI (bawaan), bypass gak dijalanin -- TAPI
--        peringatannya muncul DI DEPAN, bukan setelah 4 client nyangkut.
--        Itu sendiri nolong: dulu gejalanya cuma "client kebuka tapi diem".
--        Tambahan: client yang dipakai buat bypass dibuka JENDELA PENUH.
--        Cuma satu client yang kebuka saat itu, jadi petak grid gak ada
--        gunanya -- dan di RF 10 client petak itu cuma ~1/10 layar, tombolnya
--        jadi ~173px (v5.21: segitu susah dideteksi). Kalau client-nya udah
--        jalan duluan dengan petak kecil dan deteksi gagal, dia ditutup lalu
--        dibuka ulang penuh SEKALI -- App Cloner cuma baca posisi jendela pas
--        app MULAI, jadi gak bisa dibesarin sambil jalan.
--
-- v5.47: DUA perbaikan soal kalibrasi tombol key.
--        1. v5.46 maksa client bypass dibuka JENDELA PENUH -- itu SALAH.
--           Kalibrasi (velium_tap.txt) dikunci per UKURAN JENDELA, dan ukuran
--           petak grid itu yang udah kebukti kena. Jendela penuh bikin ukuran
--           baru yang belum terkalibrasi -> worker harus nyapu ulang percuma.
--           Sekarang: petak grid DULU, jendela penuh cuma kalau itu gagal.
--        2. Ukuran yang BELUM dikalibrasi gak lagi disapu buta -- ditebak dari
--           JUMLAH BARIS grid dulu. Data lapangan: yang nentuin posisi tombol
--           itu jumlah BARIS, bukan jumlah client (dialog Delta ukurannya
--           tetap, jadi makin pendek jendelanya makin ke bawah tombolnya):
--             1 baris -> Y 0.713   2 baris -> Y 0.723   3 baris -> Y 0.808
--           X stabil ~0.83 di semua. Jadi tebakan ini biasanya kena di
--           percobaan PERTAMA, bukan setelah nyapu belasan titik.
--
-- v5.48: FIX "lisensi hilang tapi tetep buka semua client".
--        Ada DUA blok bypass yang tabrakan:
--          * blok di loop utama (lama) jalan DULUAN, nyetel BYPASS_TERAKHIR
--          * cek di open_all (v5.46) dipanggil setelahnya -> kena cooldown
--            5 menit -> DILEWAT
--        Jadi 4 client kebuka semua tanpa bypass, nyangkut di layar key --
--        persis gejalanya. Dan blok lama itu sendiri cacat: dia milih client
--        buat nyari tombol TAPI GAK MEMBUKANYA, jadi pas worker baru nyala
--        (belum ada client jalan) dia nyari tombol di layar kosong.
--        Blok lama DIBUANG. Yang di open_all bener -- dia buka client-nya
--        dulu, tungguin layar key nongol, baru nyari tombol.
--
-- v5.49: client yang dipakai buat ambil key DITUTUP setelah bypass sukses.
--        Dia kebuka SEBELUM lisensinya ada, jadi nyangkut di layar key --
--        lisensi baru gak kebaca sama sesi yang udah jalan. Ditutup biar dia
--        ikut dibuka ULANG di urutan normal ([1/4], [2/4], ...) dengan lisensi
--        yang udah ada, jadi langsung lolos ke game.
--        Kenapa gak cukup ngandelin saringan "udah jalan": saringan itu ngecek
--        laporan bridge, dan akun ini bisa jadi masih punya laporan segar dari
--        sesi SEBELUM lisensinya abis -> kelewat, dan nyangkut selamanya.
--        Penutupan ditaruh SEBELUM potretJalan diambil, jadi potretnya udah
--        nunjukin dia mati dan dia masuk jalur buka normal.
--
-- v5.50: FIX "layar Enter key nongol tapi worker bilang lisensi ADA".
--        lisensi_keadaan() nebak dari UMUR BERKAS pakai key_jam (bawaan 24
--        jam) -- dan angka itu masih TEBAKAN, belum pernah diukur. Kalau masa
--        berlaku kunci Delta aslinya lebih pendek, berkasnya kebaca "ada"
--        padahal Delta udah minta key lagi -> bypass gak jalan, 4 client
--        nyangkut di layar key, dan gak ada tanda apa pun.
--        Layar RF gak bisa dibaca teksnya (v4.86), jadi dipakai sinyal
--        PERILAKU: client yang JALAN tapi script-nya GAK PERNAH LAPOR.
--        Sah dipakai di sini karena pemeriksaan jalan SEBELUM client dibuka --
--        yang kedapetan jalan itu sisa ronde sebelumnya, udah dapet waktu satu
--        ronde penuh (reopen_sec) buat lapor. Belum lapor = ada yang ngeblok,
--        dan layar key itu penyebab paling umum.
--
-- v5.51: FIX SETUP NGEHAPUS SETELAN MANUAL.
--        setup_wizard mulai dari `local cfg = {}` -- tabel KOSONG. Tapi
--        save_config nulis SEMUA field. Jadi setelan yang gak ditanya di
--        wizard ketulis ulang jadi bawaannya:
--          auto_key=true   -> false     (ini yang kejadian)
--          key_jam=12      -> 24
--          autoexec_bersih=false -> true
--          bypass_api_key  -> kosong
--        Gejalanya bisu: log cuma bilang "auto_key MATI", keliatan kayak
--        user-nya gak pernah nyetel.
--        Sekarang setup mulai dari config LAMA, dan yang kejaga dilaporin.
--        Plus auto_key SEKARANG DITANYA (bawaan y) -- dulu tersembunyi, cuma
--        bisa diedit manual, jadi gak ada yang tau dia ada.
--        Plus BAWAAN PERTANYAAN ikut nilai yang SEKARANG, bukan angka mati:
--          nomor tim  -> dulu selalu "1". Di RF tim-4, tekan Enter = pindah ke
--                        tim-1 DIAM-DIAM. Akun kepindah, perintah panel nyasar.
--                        Sekarang bawaannya 4, dan kalau diubah -> DIKONFIRMASI
--                        ("yakin ganti?" bawaan n), plus dijelasin akibatnya.
--          game       -> dulu selalu "1" (GAG 2). Di RF GAG 1, Enter = ganti
--                        game diam-diam, place_id ikut ganti, client join ke
--                        game yang salah.
--          script     -> ikut script yang sekarang kepakai.
--
-- v5.52: FIX "nyapu titik padahal client belum masuk game".
--        Dialog key Delta baru muncul SETELAH game kebuka. Dulu sapuan mulai
--        cuma 3 detik setelah tunggu_jalan bilang "udah jalan" -- padahal saat
--        itu client masih di halaman awal Roblox (kebukti dari layar:
--        Search/Charts/Avatar). 16 titik dihabisin buat dialog yang belum ada.
--        GAK BISA diberesin dengan nunggu activity yang lebih tepat:
--        ActivityNativeMain & MainGameActivity itu nama LAMA vs BARU buat
--        activity yang SAMA (v4.36) -- halaman awal dan di-dalam-game satu
--        activity, gak ada bedanya di mata dumpsys. Teks layar juga gak
--        kebaca (v4.86).
--        Jadi: jeda awal 3s -> 20s, DAN sapuan diulang 3 putaran berjeda 25s.
--        Jangkauannya jadi ~106 detik -- cukup buat 1 client yang kebuka
--        sendirian.
--
-- v5.53: `velium layar <client>` -- alat buat NYARI sinyal "di Home vs di game".
--        Dugaan gua di v5.52 ("gak mungkin dibedain") itu SALAH -- panel lain
--        bisa bedain, jadi sinyalnya ada, cuma belum ketemu.
--        Alat ini nge-dump 9 kandidat sekaligus: nama+state activity, daftar
--        window (dialog Delta kemungkinan jadi window sendiri), fokus layar,
--        koneksi UDP/TCP (di game harusnya ada sambungan ke server Roblox),
--        berkas log Roblox + isinya, CPU, dan memori.
--        Cara pakai: jalanin sekali pas di halaman awal, sekali pas udah di
--        game, terus bandingin. Yang beda = sinyalnya.
--
-- v5.54: `velium layar` sekarang NGUKUR SENDIRI 2x terus nunjukin BEDANYA.
--        Alurnya: hitung mundur 20s (siapin keadaan 1) -> ukur -> hitung
--        mundur 20s (user pindahin client ke game) -> ukur -> tampilin cuma
--        baris yang BERUBAH.
--        Kenapa gak nyuruh user jalanin 2x lalu nempel dua-duanya: dump
--        mentahnya panjang (9 bagian x belasan baris). Yang dibutuhin cuma
--        yang berubah, jadi alat ini yang ngerjain pembandingannya.
--
-- v5.55: `velium layar` nunjukin CLIENT-NYA YANG MANA.
--        Jendela di RF judulnya "NO MERCY DELTA LITE [64 BIT] 02/03" -- gak
--        ada nama paketnya sama sekali. Jadi user gak tau "clienu" itu jendela
--        yang mana, dan gak bisa ngarahin keadaan yang bener buat diukur.
--        Sekarang: daftar semua client + nama akun + status jalan/mati, terus
--        yang jadi target DIBAWA KE DEPAN (am start REORDER_TO_FRONT, gak
--        nge-restart game) biar jelas jendela mana yang dimaksud.
--
-- v5.56: `velium layar` nunggu ENTER, bukan hitung mundur.
--        Hitung mundur 20 detik kependekan: user masih harus nyari jendelanya,
--        tap "Tap anywhere to play", terus nungguin game-nya kebuka -- dan
--        lamanya beda-beda tergantung RF lagi berat apa nggak.
--        Enter = gak ada batas waktu, dan kendalinya di user.
--
-- v5.57: DETEKSI "UDAH DI DALAM GAME" AKHIRNYA KETEMU -- lewat MEMORI GRAFIS.
--        Hasil ukur lapangan (`velium layar`, RF aMKTN1):
--            Graphics   HOME 15.284 KB  ->  GAME 48.988 KB   (3,2x)
--        Kandidat lain gugur:
--          * jumlah window 6 vs 6 -- sama. ID-nya berubah tapi itu cuma
--            handle acak, bukan penanda.
--          * UDP/TCP keukur SE-DEVICE (/proc/net/*), bukan per-client --
--            kecampur app lain, gak bisa dipercaya. (Salah rancang di alat
--            ukurnya, bukan sinyalnya yang jelek.)
--        Graphics dari `dumpsys meminfo <pkg>` beneran per-client.
--        Ambangnya RELATIF (2x nilai awal ATAU +20 MB), bukan angka mati --
--        memori grafis ikut ukuran jendela, jadi angka tetap bakal salah di
--        RF dengan susunan grid beda. Dua aturan dipakai barengan biar
--        petak mungil (kena 2x) dan jendela besar (kena +20MB) sama-sama
--        ketangkep.
--        Sekarang sapuan tombol key nunggu SINYAL, bukan nebak 20 detik.
--
-- v5.58: BYPASS DIMULAI DARI PAPAN BERSIH -- semua client ditutup dulu.
--        Dulu client lain (statusnya latar/beku) dibiarin nyala selama bypass.
--        Dua masalahnya:
--          1. RAM kebagi. Di RF 4GB dengan 3 client nyala, sisa buat client
--             bypass tinggal sedikit -- loading game lama atau gak nyampe, dan
--             deteksi grafis (v5.57) gagal.
--          2. Client-client itu nyangkut di layar key juga -- nyala tanpa guna,
--             cuma makan tenaga.
--        Sekarang urutannya bener-bener: tutup semua -> bypass sendirian dengan
--        RAM penuh -> tutup lagi -> buka semua dari [1/4] kayak biasa.
--        Sekalian cabang "client udah jalan" dibuang -- keadaannya sekarang
--        selalu sama (semua ketutup), jadi gak perlu dua jalur. Cabang itu
--        dulu bikin jendelanya kepakai petak lama.
--
-- v5.61: LOADER DITULIS SEBAGAI velium_loader.txt (bukan .lua).
--        Dasarnya pengalaman berulang user: pakai .txt SELALU jalan.
--        Perjalanan kesimpulannya (biar gak keulang):
--          v5.59 mutusin .txt -- alasannya SALAH (nyangka text.txt kosong di
--                folder itu yang bikin jalan; padahal itu baru dibikin manual)
--          v5.60 nulis .txt + .lua sekaligus buat aman
--          v5.61 .txt doang -- keterangan langsung dari user lebih kuat, dan
--                nulis dua-duanya berisiko script jalan 2x kalau Delta ternyata
--                baca semua berkas (2x unduh, 2 salinan jalan barengan; di RF
--                4GB dengan 4 client itu pemborosan yang gak perlu).
--        Gejala aslinya ada DUA sebab numpuk: (1) nama berkas .lua, dan
--        (2) Delta nyangkut di layar "Enter key" -- autoexec gak jalan sampai
--        Delta kebuka (diberesin v5.46-5.58). Yang bikin susah dilacak: semua
--        pemeriksaan di sisi worker LOLOS, gagalnya di sisi Delta.
--
-- v5.62: FIX POSITIF PALSU di heuristik "client bisu" (v5.50).
--        Kejadian: lisensi umur 9 MENIT dicurigai basi cuma gara-gara ada 1
--        client yang belum lapor -> semua client ditutup, bypass jalan
--        percuma. Padahal masa berlaku kunci Delta gak mungkin sesingkat itu.
--        Sekarang heuristik itu cuma berlaku kalau lisensinya UDAH LEWAT
--        AMBANG UMUR (bawaan 1 jam, setel lewat curiga_jam di config).
--        Di bawah ambang -> berkasnya DIPERCAYA, gak diperiksa lebih jauh.
--        Pelajarannya: "client jalan tanpa lapor" itu sinyal LEMAH -- sebabnya
--        banyak (masih loading, panel gak kejangkau, atau nama berkas loader
--        salah kayak yang kejadian di v5.61). Dia cuma layak jadi jaring
--        pengaman buat kasus key_jam kegedean, bukan penentu utama.
--
-- v5.63: FIX deteksi "masuk game" yang kena PEMBAGIAN NOL logis.
--        Bug di v5.57: patokan grafis diambil SEKALI, tepat habis client nyala
--        -- dan saat itu nilainya masih 0.0 MB. Aturan "kini >= dasar * 2"
--        jadi "kini >= 0" yang SELALU BENAR, jadi dia ngaku "masuk game
--        setelah 5s" padahal client masih di halaman awal. Sapuan mulai
--        kecepetan -- persis masalah yang v5.57 mau beresin.
--        Sekarang DUA TAHAP:
--          1. tungguin grafis naik lalu MENDATAR (dua bacaan beda <15%, dan
--             minimal 2 MB) -> itu patokan "udah di halaman awal"
--          2. baru tungguin naik tajam dari patokan itu -> masuk game
--        Diuji 4 deret: mulai-dari-0, langsung-stabil, petak mungil, dan
--        nyangkut-di-home (yang terakhir bener-bener GAK kedeteksi).
--
-- v5.64: CADANGAN "buka ulang jendela penuh" DIBUANG.
--        Dulu (v5.46) kalau sapuan gagal, client ditutup lalu dibuka ulang
--        FULLSCREEN, alasannya "tombolnya jadi lebih gede".
--        Itu salah arah: kalibrasi tombol (velium_tap.txt) dikunci per UKURAN
--        JENDELA, dan ukuran petak grid itu yang udah kebukti kena (610x653,
--        396x293, 348x173). Jendela penuh = ukuran yang belum pernah
--        dikalibrasi -> worker malah kehilangan koordinat yang udah pasti dan
--        harus nyapu dari nol.
--        Kalau sapuan gagal, yang bener NYAPU LAGI di petak yang sama --
--        udah ditangani 3 putaran berjeda (v5.52).
--
-- v5.66: worker LAPORIN SCRIPT yang dijalanin RF ini (field "sc" di /tim).
--        Panel butuh buat misahin tab "GAG 2 farm" dari "GAG 2 seed".
--        Info per-TIM lebih andal daripada penanda per-akun: satu sumber
--        (config RF), langsung berlaku buat SEMUA akun tim itu, dan akun yang
--        belum pernah lapor pun ikut keklasifikasi -- gak perlu nunggu tiap
--        client rejoin dulu.
--
-- v5.67: Error 267 DILIAT ISI PESANNYA, bukan cuma kodenya.
--        267 = "di-kick script game" -- itu payung, sebabnya beda-beda:
--          anti-cheat / ban          -> ngulang malah makin parah (manual)
--          GAGAL MUAT DATA SIMPANAN  -> ngulang justru OBATNYA    (ulang)
--        Yang kedua rutin di GAG, dan game-nya SENDIRI nyuruh masuk ulang:
--        "Your save data didn't load right ... Please rejoin to try again."
--        Dulu dua-duanya dianggap "manual", jadi client yang cuma gagal muat
--        data nyangkut di dialog sampai ada yang mencet manual.
--
-- v5.68: SETUP OTOMATIS PENUH -- `pasang <preset>`, nol pertanyaan.
--        Pasang RF baru dulu 21 pertanyaan, 18 di antaranya selalu dijawab
--        sama. Buat 20 RF itu ratusan kali mencet Enter, dan tiap kali ada
--        peluang salah ketik yang gejalanya baru ketara berjam-jam kemudian.
--        Yang bikin ini BISA otomatis penuh cuma satu hal: NOMOR TIM diambil
--        dari server (/tim-kosong, CF v15-84), bukan diinget manusia. Sisanya
--        cuma nilai tetap.
--        Game & script dari PRESET: farm / seed / market / gag1.
--        Yang SENGAJA gak diotomatiskan -- kalau salah, seluruh sistem mati
--        tanpa gejala jelas, jadi dicek dulu dan setup BERHENTI kalau gagal:
--          * sambungan panel (URL/kunci) -> dites sebelum apa pun ditulis
--          * daftar client               -> dipindai; nol client = berhenti
--        Tanpa preset, wizard lama tetep jalan -- ada RF yang perlu setelan
--        gak biasa, dan maksa semuanya lewat preset cuma mindahin kerumitan.
--
-- v5.69: FIX `pasang <preset>` masih NANYA -- jadi klaim "sekali jalan langsung
--        jadi" itu bohong. Kejadian di lapangan: mandek di 'Kunci API
--        bypass.vip' nunggu Enter.
--        Sebabnya presetnya dibaca di UJUNG blok pasang, padahal prompt-nya
--        ada di TENGAH. Sekarang dibaca di awal, dan tiga prompt dilewat:
--          * Kunci API   -> gak perlu; kuncinya di panel (v15-64), `velium key`
--                           narik dari sana. Nanya per-RF itu ngundang salah
--                           tempel, dan kalau kuncinya ganti harus dibenerin
--                           di 20 HP satu-satu.
--          * Auto-jalan  -> langsung dipasang. RF pakai preset itu memang buat
--                           jalan terus, dan kalau ini kelewat gejalanya paling
--                           nyusahin: RF restart, semua keliatan normal, tapi
--                           worker gak pernah nyala lagi tanpa tanda apa pun.
--          * Run sekarang -> `pasang <preset>` dihitung NON_INTERAKTIF.
--
-- v5.70: FIX TERMINAL KEREBUT -- gejalanya "Termux gak bisa diketik apa pun".
--        Shell root latar dijalanin gini:
--            su -c 'sh < FIFO >> OUT 2>&1' >/dev/null 2>&1 &
--        `sh` di dalamnya dialihin ke pipa, TAPI `su` sendiri masih nempel ke
--        stdin TERMINAL. Akibatnya: (1) `su` ikut ngerebut ketikan, jadi prompt
--        keliatan nunggu tapi ketikan gak nyampe; (2) sebagian `su` naruh tty
--        ke mode raw -> carriage return ilang, keluaran menjorok makin dalam
--        tiap baris (itu yang keliatan di layar).
--        Gejalanya NYESATIN: keliatan worker-nya nyangkut, padahal
--        TERMINALNYA yang rusak.
--        Diperbaiki tiga lapis: </dev/null (stdin bukan terminal lagi),
--        setsid kalau ada (lepas dari controlling terminal), stty sane
--        setelahnya (benerin tty kalau sempat kena).
--
-- v5.71: REJOIN CEPAT dari LAPORAN KICK (star_seed v3.12 yang ngirim).
--        Dulu: client kena kick -> berhenti lapor -> nunggu auto_rejoin_menit
--        (3 menit) -> ditutup-buka, TANPA pernah tau sebabnya.
--        Sekarang script lapor dari dalam game (di situ dialognya kebaca),
--        lengkap sama sebabnya -- dan worker bisa bedain:
--          gagal-muat-data / koneksi -> rejoin SEKARANG (obatnya)
--          anti-cheat                -> JANGAN direjoin, cuma dicatet.
--        Yang kedua penting: rejoin terus ke akun kena anti-cheat itu mancing
--        hukuman lebih berat.
--        Penanda KICK_DIURUS pakai kunci "<akun>:<kick_ts>", bukan nama akun
--        doang -- satu akun bisa kena kick berkali-kali, dan tiap kejadian
--        harus diurus sendiri. Laporan lebih tua dari 5 menit dilewat, biar
--        laporan basi gak bikin rejoin berulang tiap ronde.
--
-- v5.72: REJOIN-KARENA-KICK DIJATAH. Ini KOREKSI v5.71, bukan tambahan.
--        gag2 v6.5 udah nyatet (atas permintaan sendiri):
--          "auto-rejoin (teleport balik pas 267) malah sering bikin error 267
--           LAGI -- teleport-nya sendiri ketrigger anti-cheat / data load gagal"
--        Jadi rejoin otomatis pas 267 UDAH PERNAH DICOBA DAN DIBUANG. v5.71
--        gua bikin tanpa tau itu, dan risikonya sama: badai 267.
--        Sekarang disambungin ke JATAH BUNUH yang UDAH ADA (maks 3x/30 menit
--        per client, v4.83) -- bukan penjatah kedua yang bisa beda perilaku.
--        Plus jeda 8 detik sebelum buka ulang: Roblox nolak muat data kalau
--        join-nya kerapetan, dan itu justru sumber 267 yang mau diobatin.
--        Lewat jatah -> berhenti, catet aja. 267 berulang itu bukan masalah
--        rejoin: bisa akun kena limit, atau datastore server yang rusak.
--
-- v5.73: CATATAN KEJADIAN + `velium riwayat` -- BERHENTI NEBAK, MULAI NGUKUR.
--        Log yang ada cuma 6 baris di memori, jadi pertanyaan dasar macam
--        "267-nya nempel setelah rejoin atau muncul sendiri?" GAK BISA
--        DIJAWAB -- dan tanpa itu tiap perbaikan cuma tebakan. Termasuk
--        tebakan gua sendiri di v5.71.
--        Sekarang rejoin & kick dicatet ke ~/velium_riwayat.log (append, dipangkas
--        di 2000 baris). Yang rutin TIDAK dicatet -- kalau semua dicatet, yang
--        penting ketimbun.
--        `velium riwayat` ngeringkas: jumlah per jenis, rejoin per akun + jarak
--        rata-ratanya, dan yang paling penting -- kick muncul berapa lama
--        setelah rejoin. <2 menit dominan = rejoin kita yang mancing.
--        Nyebar/lama = dari game.
--        Nama jenisnya SENGAJA cuma "KICK" dan "REJOIN". Percobaan pertama
--        pakai "REJOIN-KICK" -- nama itu ngandung dua-duanya, jadi satu
--        kejadian kehitung dua kali dan kesimpulannya ngaco. Ketangkep pas uji:
--        pola badai yang jelas malah dibilang "belum cukup data".
--
-- v5.74: CADANGAN wget kalau curl RUSAK.
--        Kejadian nyata di RF baru:
--          CANNOT LINK EXECUTABLE ".../curl": cannot locate symbol
--          "SSL_set_quic_tls_transport_params" ... libngtcp2_crypto_ossl.so
--        Itu libngtcp2 (HTTP/3) dibangun buat OpenSSL yang lebih baru dari yang
--        kepasang -- akibat upgrade Termux setengah jalan. curl mati TOTAL.
--        Dan curl itu satu-satunya jalan worker ngomong ke panel, jadi satu
--        paket rusak bikin seluruh RF diem. Titik gagal tunggal yang gak perlu
--        ada: wget hampir selalu ada dan gak kena masalah yang sama.
--        curl dites BENERAN JALAN (`curl --version` harus balikin "curl <angka>"),
--        bukan cuma dicek ada berkasnya -- kasus di atas persisnya begitu:
--        berkasnya ada, `command -v` nemu, tapi begitu dijalanin gagal link.
--        Skrip `up` juga dikasih cadangan yang sama. Kalau `up` ikut mati, gak
--        ada jalan mbenerin worker dari jauh -- harus pegang HP satu-satu.
--
-- v5.75: FIX "REJOIN SEMUA BARENG" -- akhirnya ketemu, dan ini akarnya.
--
--        bridge_fresh() balik FALSE kalau /stat gak kebaca. Itu kejadian buat
--        SEMUA akun sekaligus pas panel gak kejangkau (kuota CF habis,
--        jaringan putus, curl rusak). Akibatnya di open_all: gak ada satu pun
--        client yang lolos syarat "dilewati" -> SEMUANYA ditutup-buka, tiap
--        reopen_sec (300 detik).
--        Tiap putaran nambah satu join. Cukup banyak putaran -> Roblox nolak
--        muat data -> error 267 "Your save data didn't load right".
--
--        KEKONFIRMASI DARI DUA SISI:
--          * script jalan TANPA Termux -> gak pernah rejoin sama sekali
--          * kuota CF emang sempat habis (1027) berjam-jam, dan selama itu
--            /stat balikin halaman error terus
--
--        Yang salah bukan bacanya, tapi PERILAKU GAGALNYA: "gak bisa baca"
--        diperlakukan sama kayak "client mati". Padahal panel gak kejangkau
--        itu masalah jaringan -- bukan alasan nutup 10 client.
--        Sekarang dibedain: /stat gak kebaca -> client dibiarin apa adanya.
--        Yang beneran nyangkut tetep ketangkep jalur lain (mati mendadak,
--        auto-rejoin bridge-diem) yang gak bergantung /stat.
--
--        Jalur kedua yang kena akar sama: heuristik "curiga" di cek lisensi --
--        semua akun keliatan bisu -> lisensi sehat dicurigai basi -> semua
--        client ditutup buat bypass percuma. Ikut ditutup di sini.
-- ============================================================
CONFIG_FILE = (os.getenv("HOME") or "/data/data/com.termux/files/home") .. "/velium_worker_config.lua"
-- Backward compat: migrate old zenx files to velium if velium missing
do
  local home = os.getenv("HOME") or "."
  local function mig(old, new)
    local f1 = io.open(home.."/"..old, "r")
    local f2 = io.open(home.."/"..new, "r")
    if f1 and not f2 then f1:close(); os.execute("cp "..home.."/"..old.." "..home.."/"..new.." 2>/dev/null")
    else if f1 then f1:close() end; if f2 then f2:close() end
  end
  mig("zenx_worker_config.lua", "velium_worker_config.lua")
  mig("zenx_tap.txt", "velium_tap.txt")
  mig(".zenx_version", ".velium_version")
  mig(".zenx_aktif", ".velium_aktif")
end
end
VERSION = "9.300-cf"
-- v9.205: SPLIT tim. tim 1 (loop utama) = client 1..TIM1_AKHIR, tim 2 (borong) =
-- TIM1_AKHIR+1..total. Ubah angka ini buat ganti pembagian (default 15 -> tim1 1-15,
-- tim2 16-total). GLOBAL (bukan local) biar gak makan slot 200 main chunk.
TIM1_AKHIR = 10
-- v5.71: kick yang udah diurus, kunci = "<akun>:<kick_ts>".
-- Pakai kick_ts, bukan cuma nama akun: satu akun bisa kena kick berkali-kali,
-- dan tiap kejadian harus diurus sendiri. Kalau kuncinya nama doang, kick
-- kedua bakal dilewat dan client-nya nyangkut.
KICK_DIURUS = {}
RESTART_TS_PROSES = 0   -- v9.77: ts RESTART terakhir yg udah diproses (anti-loop, global)
DENYUT_UMUR = {}        -- v9.77: akun -> umur denyut (detik) terakhir. lapor kirim ke panel biak on/off akurat
C = { R="\27[31m",G="\27[32m",Y="\27[33m",C="\27[36m",D="\27[90m",N="\27[0m",BOLD="\27[1m",
    KRML="\27[38;5;173m", KOP="\27[38;5;130m", KRMD="\27[38;5;94m" }
LOG_KIRIM = {}          -- v9.109: SEMUA baris log (buat dikirim ke panel), maks 60
function log(m,c)
    print((c or "")..os.date("%H:%M:%S").." "..m..C.N)
    -- v9.109: catat SEMUA log (info/warn/ok/err lewat sini) -> dikirim ke panel
    -- tiap status. Biar bisa liat log RF lengkap dari panel tanpa buka Termux.
    LOG_KIRIM[#LOG_KIRIM+1] = os.date("%H:%M:%S").." "..m
    while #LOG_KIRIM > 60 do table.remove(LOG_KIRIM, 1) end
end
-- v4.24/4.26: log + "lagi ngapain" dikirim ke panel, biar gak usah pantengin Termux.
-- warn() ikut kecatet (ditandain "!") supaya ERROR keliatan di panel juga.
-- v5.30: status laporan ke panel. Dipakai buat nampilin kalau lapor GAGAL --
-- dulu gagalnya diem dan panel keliatan kosong tanpa sebab yang jelas.
LAPOR_OK, LAPOR_SEBAB, LAPOR_WARN, LAPOR_TS = nil, nil, nil, 0
AKSI_SKRG = "mulai..."  -- lagi ngapain SEKARANG
LAPOR_KEY_AT = 0        -- v4.86: kapan terakhir ngabarin "butuh key"
BAWA_SEBAB = nil       -- v5.08: kenapa gagal munculin jendela
PERTAMA_DIEM = {}      -- v5.04: kapan worker pertama liat client idup tapi bisu
BYPASS_TERAKHIR = 0   -- v5.02: kapan terakhir nyoba bypass key
SUDAH_GRID = false      -- v4.30: udah pernah nata grid sejak worker nyala?
function setAksi(txt)
    AKSI_SKRG = tostring(txt or "")
end
function catatKirim(baris)
    LOG_KIRIM[#LOG_KIRIM+1] = baris
    while #LOG_KIRIM > 20 do table.remove(LOG_KIRIM, 1) end
end

function ok(m) log("OK  "..m,C.G) end
function err(m) log("ERR "..m,C.R) end
function info(m) log("--  "..m,C.C) end

-- v9.85: DETEKSI NAIK VERSI. Simpen versi ke file tiap nyala. Pas boot,
-- bandingin file (versi lama) vs VERSION (sekarang). Kalau BEDA + file ADA =
-- baru naik (abis update) -> set WVER_NAIK = versi lama. Panel pin baris
-- "naik ke vX (dari vY)" di log. Netep sepanjang proses worker ini (gak
-- ke-scroll keluar kayak log buffer), reset pas worker restart lagi.
WVER_NAIK = nil   -- global: versi LAMA kalau baru naik (nil = boot biasa)
do
    local jalur = (os.getenv("HOME") or ".") .. "/.velium_version"
    local lama = nil
    local f = io.open(jalur, "r")
    if f then lama = (f:read("*l") or ""):gsub("%s+", ""); f:close() end
    if lama and lama ~= "" and lama ~= VERSION then
        WVER_NAIK = lama   -- naik dari `lama` ke VERSION
    end
    -- tulis versi sekarang (buat perbandingan boot berikutnya)
    local w = io.open(jalur, "w")
    if w then w:write(VERSION); w:close() end
end

-- v9.89: BOOT_TS = kapan worker ini NYALA (unix time). Dikirim ke panel tiap
-- lapor. Panel pin baris "device baru nyala HH:MM (X menit lalu)" kalau masih
-- fresh (<10 menit). Muncul TIAP reboot/update -- gak tergantung versi berubah.
BOOT_TS = os.time()
DELTA_CEK_TS = 0        -- v9.100: ts terakhir cek delta_versi.txt (auto-update 10 menit)
DELTA_SLOT_DL = {}      -- v9.104: set slot Delta yg BARU didownload (panel tandai ijo langsung)
WORKER_CEK_TS = 0       -- v9.106: ts terakhir cek versi worker (auto-update worker)
LOG_PUSH_TS = 0         -- v9.109: ts terakhir push log ke panel (tiap 60 detik)

function warn(m)
    log("!   "..m,C.Y)
    catatKirim(os.date("%H:%M:%S") .. " ! " .. tostring(m))   -- v4.26: error nongol di panel
end

-- ============================================================
-- v5.40: REPO jadi SATU konstanta, dan skrip `up` DITULIS ULANG tiap worker
-- nyala.
--
-- Kejadian nyata: `up` di RF bilang "OK 5.35" terus-terusan padahal GitHub
-- udah 5.39. Sebabnya `up` itu dibikin SEKALI pas `pasang` -- kalau RF-nya
-- dipasang pakai worker versi lama, skripnya ketinggalan selamanya, dan
-- gejalanya nyesatin: dia bilang OK, bukan gagal.
--
-- Sekarang worker nulis ulang `up` tiap nyala. Jadi sekali dapet worker baru
-- (lewat curl manual), `up`-nya kebetulin sendiri buat seterusnya.
-- Sekalian ditambah header no-cache -- jaga-jaga ada proxy di jaringan RF
-- yang gak peduli sama `?t=`.
-- ============================================================
REPO_WORKER = "https://raw.githubusercontent.com/wardz25/velium-worker/main"
-- v9.110: cek command ada gak (GLOBAL biar gak makan jatah 200 lokal main-chunk +
-- keliatan dari fungsi global auto-update). ada_perintah asli nested -> nil.
function punya_perintah(nama)
    local ok2 = os.execute("command -v " .. nama .. " >/dev/null 2>&1")
    return ok2 == true or ok2 == 0
end

function tulis_skrip_up(diam)
    local PREFIX = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
    local jalur = PREFIX .. "/bin/up"
    local isi = table.concat({
        "#!" .. PREFIX .. "/bin/sh",
        "velium stop >/dev/null 2>&1",
        'echo "narik versi baru..."',
        -- v5.74: wget dipakai kalau curl rusak.
        -- Kejadian nyata: curl gagal link gara-gara OpenSSL beda versi sama
        -- libngtcp2. Kalau `up` ikut mati, gak ada jalan lagi mbenerin worker
        -- dari jauh -- harus pegang HP-nya satu-satu.
        'URL="' .. REPO_WORKER .. '/velium_worker.lua?v=$(date +%s)"',
        'if curl --version >/dev/null 2>&1; then',
        '    curl -fsSL --compressed -H "Cache-Control: no-cache" -H "Pragma: no-cache" \\',
        '      "$URL" -o "$HOME/velium_worker.baru"',
        'elif wget --version >/dev/null 2>&1; then',
        '    echo "curl rusak -> pakai wget"',
        '    wget -q --no-cache -O "$HOME/velium_worker.baru" "$URL"',
        'else',
        '    echo "GAGAL -- curl DAN wget dua-duanya gak jalan"',
        '    echo "  betulin dulu: pkg update -y && pkg upgrade -y"',
        '    exit 1',
        'fi',
        'if head -5 "$HOME/velium_worker.baru" 2>/dev/null | grep -q "VELIUM WORKER"; then',
        '    mv "$HOME/velium_worker.baru" "$HOME/velium_worker.lua"',
        '    echo "OK  $(grep -m1 \'local VERSION\' "$HOME/velium_worker.lua")"',
        "else",
        '    echo "GAGAL -- yang keunduh bukan worker (belum di-push?)"',
        '    rm -f "$HOME/velium_worker.baru"',
        "fi",
        "",
    }, "\n")

    -- cuma ditulis kalau BEDA, biar gak nulis-nulis berkas tiap nyala
    local lama = ""
    local fr = io.open(jalur, "r")
    if fr then lama = fr:read("*all") or ""; fr:close() end
    if lama == isi then return false end

    local f = io.open(jalur, "w")
    if not f then
        if not diam then warn("gak bisa nulis " .. jalur) end
        return false
    end
    f:write(isi); f:close()
    os.execute("chmod +x " .. PREFIX .. "/bin/up")
    if not diam then ok("Skrip `up` diperbarui (anti-cache + repo terbaru)") end
    return true
end



-- ============================================================
-- config
-- ============================================================
_config_paths_dicoba = ""   -- global (bukan local -- hemat slot batas-200)
-- v9.146: NATURAL SORT -- angka dibaca sebagai ANGKA (clienu2 < clienu10), bukan
-- string sort (clienu10 < clienu2). Biar urutan client = urutan folder Download.
-- Global (bukan local) biar gak nambah local ke main chunk (limit 200).
function urut_alami(a, b)
    a, b = tostring(a), tostring(b)
    local ai, bi = 1, 1
    while ai <= #a and bi <= #b do
        local an = a:match("^%d+", ai)
        local bn = b:match("^%d+", bi)
        if an and bn then
            local na, nb = tonumber(an), tonumber(bn)
            if na ~= nb then return na < nb end
            if #an ~= #bn then return #an < #bn end   -- "01" vs "1"
            ai = ai + #an; bi = bi + #bn
        else
            local ca, cb = a:sub(ai, ai), b:sub(bi, bi)
            if ca ~= cb then return ca < cb end
            ai = ai + 1; bi = bi + 1
        end
    end
    return #a < #b
end

function load_config()
    -- v9.06: coba banyak path + INGET yg dicoba (buat debug kalau gagal).
    local paths = {
        CONFIG_FILE,
        "velium_worker_config.lua",
        "/data/data/com.termux/files/home/velium_worker_config.lua",
        (os.getenv("PWD") or ".") .. "/velium_worker_config.lua",
        (os.getenv("HOME") or ".") .. "/zenx_worker_config.lua",
        "zenx_worker_config.lua",
        "/data/data/com.termux/files/home/zenx_worker_config.lua",
    }
    _config_paths_dicoba = table.concat(paths, " | ")
    for _, path in ipairs(paths) do
        local f = io.open(path, "r")
        if f then
            local s = f:read("*all"); f:close()
            local fn = load("return " .. s)
            if fn then
                local o, cfg = pcall(fn)
                if o and type(cfg) == "table" then
                    CONFIG_FILE = path
                    -- v9.146: re-sort pkgs natural (config lama mungkin string-sort:
                    -- clienu10 sebelum clienu2). Biar idx = urutan folder Download.
                    if type(cfg.pkgs) == "string" and cfg.pkgs ~= "" then
                        local arr = {}
                        for x in cfg.pkgs:gmatch("[^,]+") do arr[#arr+1] = x end
                        table.sort(arr, urut_alami)
                        cfg.pkgs = table.concat(arr, ",")
                    end
                    -- v9.263: config lama gak punya workspace_dir -> derive biar gak nil.
                    -- dari executor kalau ada, else auto-deteksi folder, else Delta default.
                    -- NOTE: sh() belom in-scope di sini (didefinisiin belakangan), jadi pake io.popen.
                    if not cfg.workspace_dir or cfg.workspace_dir == "" then
                        if cfg.executor == "arceus" then
                            cfg.workspace_dir = "/sdcard/Arceus X/Workspace"
                        else
                            local ph = io.popen("su -c '[ -d \"/sdcard/Arceus X/Workspace\" ] && echo Y' 2>/dev/null")
                            local r = ph and ph:read("*all") or ""
                            if ph then ph:close() end
                            if r:match("Y") then
                                cfg.executor      = "arceus"
                                cfg.workspace_dir = "/sdcard/Arceus X/Workspace"
                            else
                                cfg.executor      = cfg.executor or "delta"
                                cfg.workspace_dir = "/sdcard/Delta/Workspace"
                            end
                        end
                    end
                    return cfg
                end
            end
        end
    end
    return nil
end

function save_config(cfg)
    local f=io.open(CONFIG_FILE,"w"); if not f then return false end
    f:write("{\n")
    f:write(string.format("  tim=%q,\n",cfg.tim))
    f:write(string.format("  url=%q,\n",cfg.url))
    f:write(string.format("  kunci=%q,\n",cfg.kunci))
    f:write(string.format("  targets=%q,\n",cfg.targets))
    f:write(string.format("  place_id=%q,\n",cfg.place_id))
    f:write(string.format("  game_label=%q,\n",cfg.game_label or ""))
    f:write(string.format("  script_url=%q,\n",cfg.script_url or ""))
    f:write(string.format("  script_label=%q,\n",cfg.script_label or ""))
    f:write(string.format("  link_code=%q,\n",cfg.link_code or ""))
    f:write(string.format("  autoexec_dir=%q,\n",cfg.autoexec_dir or "/sdcard/Delta/Autoexecute"))
    f:write(string.format("  executor=%q,\n",cfg.executor or "delta"))                             -- v9.263: persist executor
    f:write(string.format("  workspace_dir=%q,\n",cfg.workspace_dir or "/sdcard/Delta/Workspace"))  -- v9.263: persist path denyut
    f:write(string.format("  autoexec_bersih=%s,\n",tostring(cfg.autoexec_bersih ~= false)))
    f:write(string.format("  curiga_jam=%s,\n",tostring(tonumber(cfg.curiga_jam) or 24)))  -- v5.96: 24j (samain key_jam). 1j kekecilan -> lisensi sehat dicurigai.
    f:write(string.format("  pkgs=%q,\n",cfg.pkgs))
    f:write(string.format("  poll_sec=%d,\n",cfg.poll_sec))
    f:write(string.format("  reopen_sec=%d,\n",cfg.reopen_sec or 300))
    f:write(string.format("  auto_rejoin=%s,\n",tostring(cfg.auto_rejoin ~= false)))
    f:write(string.format("  auto_rejoin_menit=%d,\n",cfg.auto_rejoin_menit or 8))
    f:write(string.format("  stagger_sec=%d,\n",cfg.stagger_sec or 15))
    f:write(string.format("  status_sec=%d,\n",cfg.status_sec or 20))
    f:write(string.format("  win_mode=%d,\n",cfg.win_mode or 0))
    f:write(string.format("  tunggu_sec=%d,\n",cfg.tunggu_sec or 60))
    f:write(string.format("  konfirmasi_sec=%d,\n",cfg.konfirmasi_sec or 90))
    f:write(string.format("  orientasi=%q,\n",cfg.orientasi or ""))
    f:write(string.format("  keep_alive=%s,\n",tostring(cfg.keep_alive ~= false)))
    f:write(string.format("  auto_grid=%s,\n",tostring(cfg.auto_grid == true)))
    -- v9.16: SIMPAN grid_kolom biar persist antar restart. Bug: grid_kolom gak
    -- ditulis -> tiap worker restart hilang -> balik auto (SUSUNAN). User set 5
    -- kolom, restart -> balik 3 kolom (auto buat jumlah client aktif).
    f:write(string.format("  grid_kolom=%d,\n",math.floor(tonumber(cfg.grid_kolom) or 0)))
    -- v9.115: rotasi tim (borong stock). rotasi_on + daftar seed incaran.
    f:write(string.format("  rotasi_on=%s,\n",tostring(cfg.rotasi_on == true)))
    f:write(string.format("  rotasi_barang=%q,\n",cfg.rotasi_barang or ""))
    f:write(string.format("  rotasi_batch=%d,\n",math.floor(tonumber(cfg.rotasi_batch) or 5)))
    f:write(string.format("  rotasi_open_sec=%d,\n",math.floor(tonumber(cfg.rotasi_open_sec) or 80)))
    f:write(string.format("  rotasi_dunia=%q,\n",cfg.rotasi_dunia or "sama"))
    f:write(string.format("  deteksi_longgar=%s,\n",tostring(cfg.deteksi_longgar == true)))
    f:write(string.format("  disconnect_menit=%d,\n",cfg.disconnect_menit or 3))
    f:write(string.format("  jaga_depan_sec=%d,\n",cfg.jaga_depan_sec or 15))  -- v5.91: JANGAN 0 -- 0 matiin jaga_depan (jendela gak balik ke depan). Default aman 15.
    f:write(string.format("  suplai_sec=%d,\n",cfg.suplai_sec or 20))
    f:write(string.format("  shell_tetap=%s,\n",tostring(cfg.shell_tetap == true)))
    f:write(string.format("  max_coba=%d,\n",cfg.max_coba or 5))
    -- v4.78: kunci API bypass.vip. SENGAJA cuma di config (file lokal tiap RF),
    -- JANGAN dipindah ke velium_worker.lua -- itu di-push ke GitHub publik, siapa
    -- pun yang tau URL-nya bisa baca kuncinya dan ngabisin kuota.
    f:write(string.format("  bypass_api_key=%q,\n",cfg.bypass_api_key or ""))
    f:write(string.format("  key_tanda=%q,\n",cfg.key_tanda or ""))
    f:write(string.format("  key_jam=%d,\n",cfg.key_jam or 24))
    f:write(string.format("  home_detik=%d,\n",cfg.home_detik or 60))
    f:write(string.format("  auto_key=%s,\n",tostring(cfg.auto_key == true)))
    f:write(string.format("  key_tap=%q,\n",cfg.key_tap or ""))
    f:write(string.format("  gofile_token=%q,\n",cfg.gofile_token or ""))  -- v6.79: token gofile premium
    f:write(string.format("  apk_folder=%q,\n",tostring(cfg.apk_folder or "")))
    f:write(string.format("  apk_sandi=%q,\n",cfg.apk_sandi or ""))
    f:write("}\n"); f:close(); return true
end

function ask(p,d)
    io.write(C.Y.."? "..p..C.N)
    if d and d~="" then io.write(C.D.." ["..tostring(d):sub(1,44).."]"..C.N) end
    io.write(": "); io.flush()
    local i=io.read(); if i=="" then return d end; return i
end

-- ============================================================
-- shell
-- ============================================================
function sh_lama(cmd)
    -- timeout 5s: kalau cmd hang (mis. su nungguin izin), jangan freeze selamanya
    local h=io.popen("timeout 5 "..cmd.." 2>/dev/null"); if not h then return "" end
    local o=h:read("*all") or ""; h:close(); return o
end

-- ============================================================
-- v4.70: SHELL ROOT TETAP (opsional, bawaan MATI)
-- Masalahnya: tiap 'su -c ...' di RedFinger makan ~6 detik cuma buat MINTA
-- izin root. Worker manggil puluhan kali per menit -> sebagian besar waktunya
-- kebuang di situ.
-- Idenya: buka SATU shell root di awal, biarin nyala, lempar perintah ke situ.
-- Ongkos ~6 detik itu cuma dibayar SEKALI.
--
-- Pengaman (biar aman dicoba):
--   * dites dulu pas nyala -- gagal = balik ke cara lama, gak ada yang rusak
--   * tiap perintah dibungkus 'timeout' DI DALAM shell -> satu macet gak nahan
--     antrean di belakangnya
--   * tiap perintah punya penanda unik -> jawaban gak mungkin ketuker
--   * kalau shell-nya mati di tengah jalan, kedeteksi & balik ke cara lama
-- ============================================================
SHELL_AKTIF   = false      -- lagi kepakai apa nggak
SHELL_TULIS   = nil        -- pipa buat ngirim perintah
-- v4.75: dulu di /data/local/tmp -- itu punya root, Termux gak bisa bikin file
-- di situ, jadi mkfifo gagal diem-diem lalu "gagal buka pipa". Pakai folder
-- Termux sendiri: pasti bisa ditulis, dan root tetep bisa baca.
RUMAH     = os.getenv("HOME") or "."
SHELL_IN  = RUMAH .. "/.velium_in"
SHELL_OUT = RUMAH .. "/.velium_out"
SHELL_URUT = 0

function shell_matikan()
    if SHELL_TULIS then pcall(function() SHELL_TULIS:close() end) end
    SHELL_TULIS, SHELL_AKTIF = nil, false
    os.execute("rm -f " .. SHELL_IN .. " " .. SHELL_OUT .. "* >/dev/null 2>&1")
end

-- kirim satu perintah ke shell tetap. balikin: keluaran, atau nil kalau gagal
function shell_jalan(cmd, batas)
    if not SHELL_AKTIF or not SHELL_TULIS then return nil end
    SHELL_URUT = SHELL_URUT + 1

    -- v4.77: tiap perintah nulis ke file SENDIRI, terus bikin file penanda
    -- "selesai". Dulu semua nulis ke satu file yang terus kebuka -- keluarannya
    -- nyangkut di penyangga (shell nulis ke file itu numpuk dulu di memori),
    -- jadi jawabannya gak pernah nyampe. Begitu redirect '>' nutup (perintah
    -- kelar), isinya PASTI ketulis -- gak ada yang nyangkut.
    local fOut  = SHELL_OUT .. "." .. SHELL_URUT
    local fDone = SHELL_OUT .. "." .. SHELL_URUT .. ".ok"
    local aman  = "'" .. tostring(cmd):gsub("'", "'\\''") .. "'"

    local ok = pcall(function()
        SHELL_TULIS:write("timeout " .. (batas or 8) .. " sh -c " .. aman ..
                          " > " .. fOut .. " 2>/dev/null; echo x > " .. fDone .. "\n")
        SHELL_TULIS:flush()
    end)
    if not ok then shell_matikan(); return nil end

    -- tungguin penanda selesai muncul
    local mulai = os.time()
    while (os.time() - mulai) <= (batas or 8) + 3 do
        local d = io.open(fDone, "r")
        if d then
            d:close()
            local hasil = ""
            local f = io.open(fOut, "r")
            if f then hasil = f:read("*all") or ""; f:close() end
            os.remove(fOut); os.remove(fDone)
            return hasil
        end
        os.execute("sleep 0.2")
    end
    os.remove(fOut); os.remove(fDone)
    -- gak ada jawaban -> anggap shell-nya bermasalah, balik ke cara lama
    shell_matikan()
    return nil
end

function shell_nyalakan()
    -- pastiin su beneran jalan dulu (kalau nggak, jangan nekat buka pipa:
    -- io.open ke FIFO bakal nunggu selamanya kalau gak ada yang baca)
    local tes = sh_lama("su -c 'echo VELIUMOK'")
    if not tes:find("VELIUMOK", 1, true) then return false, "su gak jalan" end

    os.execute("rm -f " .. SHELL_IN .. " " .. SHELL_OUT .. " >/dev/null 2>&1")
    os.execute("mkfifo " .. SHELL_IN .. " >/dev/null 2>&1")
    os.execute("touch " .. SHELL_OUT .. " >/dev/null 2>&1")
    -- pastiin pipanya beneran kebikin (mkfifo bisa gagal diem-diem)
    local adaPipa = sh_lama("test -p " .. SHELL_IN .. " && echo ADA")
    if not adaPipa:find("ADA", 1, true) then
        return false, "mkfifo gak jalan (pkg install coreutils?)"
    end
    -- ============================================================
    -- v5.70: shell root DILEPAS dari terminal.
    --
    -- Dulu: su -c '...' >/dev/null 2>&1 &
    -- `sh` di dalamnya dialihin ke pipa, TAPI `su` sendiri masih nempel ke
    -- stdin terminal. Dua akibatnya, dan dua-duanya kejadian di lapangan:
    --   1. `su` ikut ngerebut apa yang diketik -> prompt keliatan nunggu tapi
    --      ketikan gak nyampe. Kesannya Termux hang.
    --   2. sebagian implementasi `su` naruh tty ke mode raw -> carriage return
    --      ilang, dan keluaran jadi menjorok makin dalam tiap baris.
    -- Gejalanya nyesatin: keliatan kayak worker-nya nyangkut, padahal
    -- terminalnya yang rusak.
    --
    -- Tiga lapis biar bener-bener lepas:
    --   </dev/null  -> stdin su gak lagi terminal
    --   setsid      -> lepas dari controlling terminal (kalau ada)
    --   stty sane   -> benerin tty setelahnya, kalau sempat kena
    -- ============================================================
    -- v5.70: dicek pakai `command -v`, BUKAN ada_perintah() -- fungsi itu
    -- lokal di dalam blok `pasang` (baris ~6395) dan GAK ADA di sini.
    -- Manggilnya bakal "attempt to call a nil value" dan shell root gagal
    -- total. Ketangkep pas ngecek urutan deklarasi.
    local pakaiSetsid = ""
    if sh_lama("command -v setsid >/dev/null 2>&1 && echo ADA"):find("ADA", 1, true) then
        pakaiSetsid = "setsid "
    end
    os.execute(pakaiSetsid .. "su -c 'sh < " .. SHELL_IN .. " >> " .. SHELL_OUT ..
               " 2>&1' </dev/null >/dev/null 2>&1 &")
    os.execute("sleep 1")
    -- benerin terminal kalau `su` sempat ngerusak line discipline-nya.
    -- Murah, dan gak ngefek apa-apa kalau ternyata aman.
    os.execute("stty sane 2>/dev/null")

    local f = io.open(SHELL_IN, "w")
    if not f then shell_matikan(); return false, "gagal buka pipa" end
    SHELL_TULIS, SHELL_AKTIF = f, true

    -- tes beneran: harus balik jawaban yang bener
    local uji = shell_jalan("echo VELIUMSIAP", 5)
    if not uji or not uji:find("VELIUMSIAP", 1, true) then
        shell_matikan(); return false, "shell gak jawab"
    end
    return true
end

-- Perintah yang ada udah dibungkus "su -c '...'". Kalau dijalanin DI DALAM
-- shell yang emang udah root, bungkus itu bakal manggil su LAGI -- percuma,
-- ongkosnya balik kayak semula. Jadi bungkusnya dibuka dulu.
function buka_bungkus_su(cmd)
    local isi = cmd:match("^su %-c '(.*)'$") or cmd:match('^su %-c "(.*)"$')
    if isi then
        -- balikin escape yang dipakai pas ngebungkus
        isi = isi:gsub('\\"', '"')
        return isi
    end
    return cmd
end

-- pintu masuk tunggal: coba shell tetap dulu, gagal -> cara lama
function sh(cmd)
    if SHELL_AKTIF then
        local o = shell_jalan(buka_bungkus_su(cmd), 8)
        if o then return o end
        -- shell_jalan udah matiin dirinya kalau bermasalah -> lanjut ke cara lama
    end
    return sh_lama(cmd)
end
-- v9.147: sh dengan timeout custom (buat command yg skala jumlah client, mis.
-- deteksi running 20 client -- default 8s kepotong -> client terakhir gak kebaca).
-- GLOBAL (bukan local) biar gak nambah slot batas-200.
function sh_tmo(cmd, tmo)
    tmo = tmo or 8
    if SHELL_AKTIF then
        local o = shell_jalan(buka_bungkus_su(cmd), tmo)
        if o then return o end
    end
    local h = io.popen("timeout " .. tmo .. " " .. cmd .. " 2>/dev/null")
    if not h then return "" end
    local o = h:read("*all") or ""; h:close(); return o
end
function sh_silent(cmd)
    if SHELL_AKTIF then
        if shell_jalan(buka_bungkus_su(cmd), 8) then return end
    end
    os.execute("timeout 8 "..cmd.." >/dev/null 2>&1")
end

function split(s,sep)
    local t={}
    for x in tostring(s or ""):gmatch("[^"..(sep or ",").."]+") do
        x=x:gsub("^%s+",""):gsub("%s+$","")
        if x~="" then t[#t+1]=x end
    end
    return t
end

function shq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

-- ============================================================
-- v4.78: BYPASS KEY DELTA (api.bypass.vip)
-- Link key-system Delta (auth.platorelay.com/a?d=...) dilempar ke API, API-nya
-- yang nyelesaiin checkpoint. Jadi gak usah tempel-tempel manual.
--
-- Kenapa gak lewat sh() biasa: sh() dipatok timeout 5-8 detik (emang sengaja --
-- biar 'su' yang hang gak nahan worker). Bypass butuh 30-60 detik. Kalau maksa
-- lewat sh(), hasilnya SELALU kepotong dan keliatan kayak "API-nya gagal".
-- Lagipula curl ke internet gak butuh root, jadi gak usah lewat su sama sekali.
-- ============================================================
BYPASS_BASE    = "https://api.bypass.vip/premium/bypass?url="
BYPASS_REFRESH = "https://api.bypass.vip/premium/refresh?url="

-- ============================================================
-- v5.33: KUNCI API BAWAAN, ditaruh langsung di sini.
--
-- KENAPA BOLEH: repo `revsy` itu PRIVAT. Kalau suatu saat repo-nya dijadiin
-- publik, KOSONGIN baris ini duluan -- ini kunci langganan berbayar, siapa
-- pun yang bisa baca file ini bisa ngabisin kuotanya.
--
-- Dipakai LANGSUNG tanpa nanya panel, jadi nol delay. Panel cuma dipakai
-- kalau baris ini dikosongin.
--
-- Mau ganti kunci? Ubah di sini, push, terus `up` di tiap RF.
-- Mau satu RF pakai kunci beda? `velium key set <APIKEY>` -- config lokal menang.
-- ============================================================
BYPASS_KEY_BAWAAN = "621eeee7-973c-4789-a605-138214d87873"

function url_encode(s)
    return (tostring(s or ""):gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- ambil link dari clipboard Termux (butuh termux-api). balikin nil kalau gak ada.
function clipboard_ambil()
    local h = io.popen("timeout 10 termux-clipboard-get 2>/dev/null")
    if not h then return nil end
    local s = (h:read("*all") or ""):gsub("^%s+", ""):gsub("%s+$", "")
    h:close()
    if s == "" then return nil end
    return s
end

-- v5.31: DEKLARASI MAJU. ambil_apikey butuh api_get & ambil_str yang
-- dideklarasi jauh di bawah, tapi bypass_kunci (di sini) butuh ambil_apikey.
-- Dua-duanya gak bisa ditaruh duluan. Jadi namanya dipesan dulu di sini,
-- isinya diisi setelah api_get ada. Ini pola baku buat lingkaran begini --
-- dan WAJIB, kalau nggak bakal "attempt to call a nil value" pas jalan
-- (jebakan 5.14: luac -p GAK nangkep ini).
ambil_apikey = nil

-- panggil API bypass. balikin: kunci, pesanError, jawabanMentah
function bypass_kunci(cfg, link, pakaiRefresh)
    local apikey, asal = ambil_apikey(cfg)
    if apikey == "" then
        return nil, "kunci API bypass.vip belum ada.\n" ..
                    "   Isi BYPASS_KEY_BAWAAN di velium_worker.lua, atau\n" ..
                    "   per-RF: velium key set <APIKEY>", nil
    end
    if asal ~= "config" then info("kunci API dari " .. asal) end
    if not link or link == "" then return nil, "link kosong", nil end
    if not link:find("^https?://") then
        return nil, "yang dikasih bukan link (harus mulai http/https)", nil
    end

    local dasar = pakaiRefresh and BYPASS_REFRESH or BYPASS_BASE
    -- timeout 90: API-nya emang lama (dia yang ngerjain checkpoint-nya)
    local cmd = string.format("timeout 90 curl -s -4 -m 85 -H %s %s 2>/dev/null",
        shq("x-api-key: " .. apikey), shq(dasar .. url_encode(link)))
    local h = io.popen(cmd)
    if not h then return nil, "gagal jalanin curl", nil end
    local jawab = h:read("*all") or ""
    h:close()

    if jawab:gsub("%s+", "") == "" then
        return nil, "API gak jawab (internet mati / kelamaan / kuota abis?)", jawab
    end

    -- v4.78: bentuk JSON-nya belum pernah dilihat langsung, jadi JANGAN dikunci
    -- ke satu nama field. Dicoba beberapa nama yang lazim; kalau meleset semua,
    -- jawaban MENTAH-nya dicetak -- dari situ baru dikunci ke bentuk aslinya.
    for _, k in ipairs({ "result", "key", "response", "bypassed", "data" }) do
        local v = jawab:match('"' .. k .. '"%s*:%s*"(.-)"')
        if v and v ~= "" then return v, nil, jawab end
    end

    -- ada pesan error dari API-nya?
    local e = jawab:match('"error"%s*:%s*"(.-)"')
            or jawab:match('"message"%s*:%s*"(.-)"')
    if e and e ~= "" then return nil, "API bilang: " .. e, jawab end

    return nil, "jawaban API gak dikenali bentuknya", jawab
end

-- ============================================================
-- v4.80: TULIS KUNCI KE DELTA
-- Ketemu lewat potret sebelum-sesudah: pas kunci ditempel manual, yang muncul
-- file /sdcard/Delta/Internals/Cache/license -- isinya kunci POLOS, 37 byte
-- (FREE_ + 32 hex), TANPA baris baru dan tanpa bungkus JSON.
-- Letaknya di /sdcard (bukan /data/data/<paket>), jadi SATU file ini kepakai
-- semua client sekaligus -- gak usah per-client.
-- ============================================================
DELTA_LICENSE = "/sdcard/Delta/Internals/Cache/license"

function tulis_lisensi(cfg, kunci)
    local path = (cfg and cfg.delta_license) or DELTA_LICENSE
    local dir  = path:match("^(.*)/") or "/sdcard/Delta/Internals/Cache"

    -- 1) coba tulis langsung. Termux yang udah dikasih izin penyimpanan
    -- biasanya boleh nulis di /sdcard, jadi gak usah repot manggil root.
    local f = io.open(path, "w")
    if f then
        f:write(kunci)          -- TANPA baris baru: aslinya emang pas 37 byte
        f:close()
    else
        -- 2) gak boleh nulis langsung -> lewat root. Ditulis ke file sementara
        -- dulu baru disalin, biar gak kejebak neraka tanda kutip di dalam su.
        local tmp = (os.getenv("HOME") or ".") .. "/.velium_lic.tmp"
        local g = io.open(tmp, "w")
        if not g then return false, "gak bisa bikin file sementara" end
        g:write(kunci); g:close()
        sh("su -c 'mkdir -p " .. dir .. "; cp " .. tmp .. " " .. path ..
           "; chmod 660 " .. path .. "'")
        os.remove(tmp)
    end

    -- 3) BACA ULANG. Nulis "berhasil" gak ada artinya kalau isinya gak nyampe --
    -- dan kalau salah, lo baru sadar pas semua client gagal masuk.
    local isi = nil
    local cek = io.open(path, "r")
    if cek then isi = cek:read("*all"); cek:close() end
    if not isi or isi:gsub("%s+", "") == "" then
        isi = sh("su -c 'cat " .. path .. "'")   -- cadangan: baca pakai root
    end
    isi = (isi or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if isi ~= kunci then
        return false, "ketulis tapi isinya beda (kebaca: '" .. isi:sub(1, 45) .. "')"
    end
    return true, path
end

-- v4.79: tulis kunci API ke config TANPA setup ulang.
-- Sengaja EDIT TERTARGET (baca teksnya, ganti/sisipin satu baris) -- bukan
-- load_config lalu save_config. Alasannya: save_config cuma nulis daftar
-- setelan yang dia kenal, jadi kalau ada setelan yang ditambah manual di
-- config, itu bakal KEHAPUS diem-diem. Cara ini gak nyentuh baris lain.
--
-- v4.81 (PENTING): dulu urutannya TULIS DULU baru dicek. Pas pengecekannya
-- gagal, config-nya udah terlanjur ketimpa rusak -- worker jadi gak mau nyala
-- sama sekali. Sekarang dibalik: hasil editan DITES DI MEMORI dulu, baru
-- ditulis kalau sah. Gagal = config lama gak disentuh sedikit pun.
-- v4.86: KEADAAN LISENSI DELTA.
-- Layar gak bisa dibaca (kebukti: game/key/Home sama-sama 0 teks), jadi "lagi
-- diminta key apa nggak" ditebak dari BERKASNYA -- itu kebaca jelas:
--   /sdcard/Delta/Internals/Cache/license   37 byte, isinya kunci polos
-- Kalau berkasnya HILANG atau UMURNYA lewat batas, hampir pasti Delta minta
-- key lagi. Dalam keadaan itu client JANGAN dibunuh -- restart gak bikin kunci
-- masuk, cuma muter-muter sambil ngabisin RAM.
-- balikin: "ada" / "hilang" / "basi", umur dalam detik (nil kalau hilang)
function lisensi_keadaan(cfg)
    -- v9.295: ARCEUS gak pakai lisensi Delta (executor beda -- gak ada berkas kunci
    -- Delta, gak ada layar "Enter key"). Anggap "ada" biar SEMUA cek lisensi lolos
    -- (start, antrian/denyut-rejoin, bypass, cek berkala) tanpa nyangkut.
    if cfg and cfg.executor == "arceus" then return "ada", 0 end
    local path = (cfg and cfg.delta_license) or DELTA_LICENSE

    -- v5.96: PENENTU UTAMA = ISI FILE, bukan umur. Kebukti di lapangan:
    --   * lisensi VALID   = file ada, isi "FREE_<hash 32 hex>" (37 byte)
    --   * key HABIS        = file HILANG (Delta hapus). cat -> kosong.
    -- Umur file GAK ANDAL (key_jam cuma tebakan) -- dan bikin positif palsu:
    -- lisensi sehat umur 1j45m dicurigai basi -> tutup semua + bypass percuma.
    -- Jadi: cek isinya. Ada key-nya = valid, titik. Gak usah nebak umur.
    -- v7.69: CEK 3X (user minta). 'su -c cat' kadang GAGAL (su lambat/timeout di
    -- RF) -> balik kosong -> dikira "hilang" padahal ADA -> bypass percuma /
    -- mode salah. Sekarang: coba baca sampai 3x, begitu dapet isi valid -> pakai.
    -- Cuma nyerah "hilang" kalau 3x tetep kosong (beneran gak ada).
    local isi = ""
    local adaKey = nil
    for coba = 1, 3 do
        isi = sh("su -c 'cat " .. path .. " 2>/dev/null'") or ""
        adaKey = isi:match("FREE_%x+") or isi:match("[%w_]-%x%x%x%x%x%x%x%x%x%x")
        if adaKey and #isi:gsub("%s", "") >= 20 then
            break   -- dapet key valid -> stop retry
        end
        if coba < 3 then os.execute("sleep 1") end   -- jeda sebelum coba lagi
    end
    if adaKey and #isi:gsub("%s", "") >= 20 then
        -- masih hitung umur buat INFO (ditampilin), tapi BUKAN penentu basi.
        local o = sh("su -c 'stat -c %Y " .. path .. " 2>/dev/null'") or ""
        local ts = tonumber(o:match("%d+"))
        local umur = ts and (os.time() - ts) or nil
        return "ada", umur
    end
    -- isi kosong / file hilang / key gak kebentuk -> beneran habis (setelah 3x)
    return "hilang", nil
end

function umur_ringkas(detik)
    if not detik then return "?" end
    local j = math.floor(detik / 3600)
    local m = math.floor((detik % 3600) / 60)
    if j > 0 then return j .. "j " .. m .. "m" end
    return m .. "m"
end

-- v4.92: DIPINDAH KE ATAS. Di Lua fungsi lokal gak diangkat ke atas --
-- kalau dideklarasi di bawah tapi dipanggil di atas, isinya masih nil.
-- rekam_sentuh manggil ini, jadi harus kedefinisi duluan.

-- ============================================================
-- v4.25: ATUR GRID â€” susun jendela freeform biar gak numpuk.
-- Butuh client jalan di mode freeform (win_mode 5). Caranya:
--   1. baca ukuran layar (wm size)
--   2. cari taskId tiap client (dumpsys)
--   3. am task resizeTask <taskId> kiri atas kanan bawah
-- CATATAN: 'am task resizeTask' gak ada di semua ROM. Kalau gagal, dilaporin
-- ke log (gak diem-diem), dan client tetep jalan normal -- cuma gak ketata.
-- ============================================================
function layar_ukuran()
    -- "Physical size: 720x1280" (kadang ada "Override size:" -> itu yang dipakai)
    local o = sh("su -c 'wm size'") or ""
    local w, h = o:match("Override size:%s*(%d+)x(%d+)")
    if not w then w, h = o:match("Physical size:%s*(%d+)x(%d+)") end
    w, h = tonumber(w) or 0, tonumber(h) or 0
    if w == 0 or h == 0 then return 0, 0, 0 end

    -- v4.27: 'wm size' itu ukuran FISIK, GAK ikut muter pas layar landscape.
    -- Kalau lagi landscape, lebar/tinggi efektifnya KEBALIK -> harus dituker,
    -- kalau nggak grid-nya ngitung pakai bentuk portrait (jendela kepencet /
    -- keluar layar). rotasi: 0=portrait, 1=landscape, 2=portrait kebalik, 3=landscape kebalik.
    local rot = tonumber((sh("su -c 'settings get system user_rotation'") or ""):match("%d+"))
    if not rot then
        -- cadangan: baca dari window manager
        local d = sh("su -c 'dumpsys window | grep -m1 -E \"mCurrentRotation|mRotation\"'") or ""
        rot = tonumber(d:match("[Rr]otation[=:%s]*(%d+)")) or 0
    end
    if rot == 1 or rot == 3 then w, h = h, w end
    return w, h, rot
end

-- v5.14: DIPINDAH KE ATAS. Perintah panjang (nyari tombol, pantau sentuhan)
-- perlu ngecek tanda berhenti, dan mereka dideklarasi jauh di atas sini.
PID_FILE  = "velium_worker.pid"
STOP_FILE = "velium_worker.stop"

function ada_stop()
    local f = io.open(STOP_FILE, "r")
    if f then f:close(); return true end
    return false
end

-- v9.63: helper ada_perintah_baru dipindah ke SETELAH api_get didefinisiin
-- (v9.69 fix: dulu di sini -> api_get masih nil -> worker crash baris 1278).
_apb_cache = false
_apb_waktu = 0

-- v4.89: BAWA JENDELA KE DEPAN TANPA LINK JOIN.
-- Dulu munculinnya pakai 'am start -d <link>'. Itu aman kalau client UDAH di
-- dalam game (link jadi no-op), TAPI kalau lagi di layar key / belum masuk
-- game, link itu BENERAN dieksekusi -> client join & teleport sendiri. Kejadian
-- pas kalibrasi tap: client malah pindah ke market.
-- Sekarang: pindahin task-nya doang, gak nyentuh isi aplikasi sama sekali.
function bawa_depan(pkg)
    -- 1) lewat taskId. Di RedFinger cuma 'am stack list' yang ngasih taskId
    -- (dumpsys activity gagal). Keluarannya suka ke-wrap, jadi dibaca pakai
    -- posisi, bukan per baris.
    local o = sh("su -c 'am stack list 2>&1'") or ""
    local id, cari = nil, 1
    while true do
        local _, b = o:find("taskId=", cari, true)
        if not b then break end
        local nomor = o:match("^(%d+)", b + 1)
        if nomor and o:sub(b, b + 200):find(pkg, 1, true) then id = nomor break end
        cari = b + 1
    end
    if id then
        local r = sh("su -c 'am task move-task " .. id .. " true 2>&1'") or ""
        if not r:lower():find("unknown") and not r:lower():find("exception") then
            return true, "task " .. id
        end
        BAWA_SEBAB = "move-task ditolak: " .. (r:gsub("%s+", " "):sub(1, 40))
    else
        -- v5.08: kenapa taskId gak ketemu -- ini yang bikin jatuh ke cara cadangan
        BAWA_SEBAB = (o:match("%S") and "taskId gak ada di keluaran 'am stack list'")
                     or "'am stack list' gak ngasih apa-apa"
    end
    -- 2) cadangan: panggil activity-nya langsung, TANPA -d (tanpa link)
    sh_silent("su -c 'am start -f 0x20000000 -n " .. pkg ..
              "/com.roblox.client.startup.MainGameActivity'")
    return true, "activity"
end

-- v4.88: baca KOTAK JENDELA client yang sebenernya (bukan hitungan grid).
-- Dari dump: bounds="[688,167][1089,500]". Semua simpul bounds-nya sama karena
-- isi jendela digambar ke permukaan -- tapi justru itu yang kita mau: kotak
-- luar jendelanya.
-- v5.08: PASTIIN client beneran yang di depan, jangan cuma "udah disuruh naik".
-- Client itu jendela NGAMBANG kecil. Habis baca papan klip, Termux nutupin
-- layar penuh -- kalau 'input tap' ditembak ke koordinat client sementara
-- Termux masih di atas, yang nerima pencetan itu TERMUX. Koordinatnya bener,
-- yang salah urutan tumpukannya.
-- Jadi: disuruh naik -> DIPERIKSA lewat mCurrentFocus -> diulang kalau belum.
function pastikan_depan(pkg, maks)
    for coba = 1, (maks or 3) do
        bawa_depan(pkg)
        os.execute("sleep 2")
        local fokus = sh("su -c 'dumpsys window | grep mCurrentFocus'") or ""
        if fokus:find(pkg, 1, true) then return true, coba end
    end
    local fokus = sh("su -c 'dumpsys window | grep mCurrentFocus'") or ""
    local siapa = fokus:match("([%w%.]+)/") or "?"
    return false, siapa
end

-- v5.07 (BUG PENTING): dulu fungsi ini cuma motret layar yang lagi DI DEPAN,
-- tanpa mastiin itu beneran client-nya. Padahal di alur nyari tombol, Termux
-- sering lagi di depan (abis baca papan klip) -- jadi yang keukur JENDELA
-- TERMUX, dan semua tap dihitung dari kotak yang salah. Itu sebabnya
-- pencetannya nyasar ke Termux, bukan ke client.
-- Sekarang: client dipaksa ke depan dulu, hasilnya DIVERIFIKASI (dump-nya harus
-- beneran punya paket itu), dan kotaknya cuma diambil dari simpul milik paket
-- itu -- bukan simpul terbesar apa pun yang kebetulan ada.
function jendela_kotak(pkg)
    local dump = "/sdcard/velium_kotak.xml"
    -- v6.13: pastikan_depan DIBUANG. Logika user (bener): kalau client di petak
    -- (freeform), dia UDAH di depan -- ukur langsung. Kalau ketutup/fullscreen,
    -- paksa-depan cuma goyangin fokus (bikin Termux nyelonong -> tap nyasar).
    -- Ganti: ukur apa adanya. Yang manggil yang mutusin (kalau kotak salah ->
    -- buka ulang Roblox, bukan paksa depan).
    for coba = 1, 2 do
        -- hapus+dump+baca+hapus digabung jadi SATU panggilan su (tiap 'su' ~6 detik)
        local isi = sh("su -c 'rm -f " .. dump .. "; uiautomator dump " .. dump ..
                       " >/dev/null 2>&1; cat " .. dump .. " 2>/dev/null; rm -f " .. dump .. "'") or ""
        if isi:find("bounds", 1, true) then
            -- dump-nya beneran punya client ini?
            if isi:find('package="' .. pkg .. '"', 1, true) then
                -- ambil kotak TERBESAR DI ANTARA SIMPUL MILIK PAKET INI
                local bL, bT, bR, bB, luasMax = nil, nil, nil, nil, -1
                for simpul in isi:gmatch("<node[^>]*>") do
                    if simpul:find('package="' .. pkg .. '"', 1, true) then
                        local x1, y1, x2, y2 = simpul:match(
                            'bounds="%[(%-?%d+),(%-?%d+)%]%[(%-?%d+),(%-?%d+)%]"')
                        if x1 then
                            x1, y1, x2, y2 = tonumber(x1), tonumber(y1), tonumber(x2), tonumber(y2)
                            local luas = (x2 - x1) * (y2 - y1)
                            if luas > luasMax then
                                luasMax = luas; bL, bT, bR, bB = x1, y1, x2, y2
                            end
                        end
                    end
                end
                if bL then return { L = bL, T = bT, R = bR, B = bB } end
            end
        end
        -- yang kepotret bukan client ini -> coba sekali lagi
    end
    return nil, "yang di depan bukan " .. pkg:gsub("com%.roblox%.", "") ..
                " (client-nya jalan? jendelanya nongol?)"
end

-- v4.88: pencet titik di dalam jendela client, ditunjuk pakai PECAHAN (0..1)
-- dari kotak jendelanya -- bukan koordinat layar. Jadi angka yang sama kepakai
-- di semua client, walau petaknya beda-beda.
-- v5.07: 'kotak' boleh dioper dari luar -- kalau udah diukur, gak usah diukur
-- ulang. Ngukur itu 2 panggilan su (~12 detik); pas nyapu 8 titik, itu doang
-- bisa makan 1,5 menit percuma.
function tap_jendela(cfg, pkg, fx, fy, kali, kotak)
    -- v6.11: JANGAN PERNAH TAP SEBELUM NGUKUR. Aturan tegas: tiap tap WAJIB
    -- ukur jendela fresh (jendela_kotak). Kotak yang dioper dari luar bisa BASI
    -- (jendela udah pindah/fullscreen sejak diukur) -> tap pakai koordinat lama
    -- -> nyasar ke app lain (Termux). Jadi kotak dari luar cuma dipakai sebagai
    -- PETUNJUK; kotak asli tetep diukur ulang di sini.
    local ukur = jendela_kotak(pkg)
    if not ukur then
        -- v7.55: uiautomator dump GAGAL (sering pas di DALAM GAME -- game render
        -- pakai surface, gak ada view hierarchy). Fallback: baca posisi window
        -- dari PREFS App Cloner (app_cloner_current_window_*) -- reliable, gak
        -- butuh uiautomator. Ini yang bikin sapu key gagal di 10 client.
        local ppath = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
        local isiP = sh("su -c 'cat " .. ppath .. " 2>/dev/null'") or ""
        local L = tonumber(isiP:match('<int name="app_cloner_current_window_left" value="(%-?%d+)"'))
        local T = tonumber(isiP:match('<int name="app_cloner_current_window_top" value="(%-?%d+)"'))
        local R = tonumber(isiP:match('<int name="app_cloner_current_window_right" value="(%-?%d+)"'))
        local B = tonumber(isiP:match('<int name="app_cloner_current_window_bottom" value="(%-?%d+)"'))
        if L and T and R and B and (R - L) > 50 then
            ukur = { L = L, T = T, R = R, B = B }
            info(("   ukur jendela dari prefs App Cloner (%dx%d) -- uiautomator gagal"):format(R-L, B-T))
        else
            return nil, "gagal ukur jendela sebelum tap -- tap dibatalin (gak nebak koordinat)"
        end
    end
    kotak = ukur
    -- PENGAMAN: TOLAK tap kalau kotak FULLSCREEN (lebar > 1000). Jendela belum
    -- settle ke petak -> koordinat pecahan jatuh di luar petak -> kena app lain.
    local lebarK = kotak.R - kotak.L
    if lebarK > 1000 then
        return nil, ("jendela masih fullscreen (%d) -- tap DITOLAK biar gak nyasar ke app lain"):format(lebarK)
    end
    -- v7.67: CEK LAYAR/JENDELA BENER dulu (user minta). Pastiin ukuran jendela
    -- WAJAR (bukan kekecilan/nol -- tanda jendela belum settle di posisi grid).
    -- Kalau jendela belum pas (lagi pindah/loading), tap ditunda -> gak hempas
    -- titik nyasar. Petak 10 client ~200-230px; kalau <100 berarti belum settle.
    local tinggiK = (kotak.B or 0) - (kotak.T or 0)
    if lebarK < 100 or tinggiK < 100 then
        return nil, ("jendela belum settle (%dx%d) -- tap DITUNDA (nunggu posisi grid)"):format(lebarK, tinggiK)
    end
    -- v6.13: VERIFIKASI client BENERAN DI DEPAN tepat sebelum tap. Bahaya:
    -- antara ukur & tap, Termux bisa nyelonong ke depan (abis baca clipboard,
    -- Termux layar penuh nutupin petak). Kalau tap jalan pas Termux di depan,
    -- koordinat petak yang bener tetep KENA TERMUX (yang nangkring di situ).
    -- Cek fokus: kalau bukan client ini di depan -> BATAL, jangan tap.
    local fokus = sh("su -c 'dumpsys window | grep mCurrentFocus'") or ""
    if not fokus:find(pkg, 1, true) then
        local siapa = fokus:match("([%w%.]+)/") or "?"
        return nil, ("yang di depan " .. siapa:gsub("com%.roblox%.","") ..
                     ", bukan " .. pkg:gsub("com%.roblox%.","") .. " -- tap DIBATALIN (anti-nyasar)")
    end
    local x = math.floor(kotak.L + (kotak.R - kotak.L) * fx)
    local y = math.floor(kotak.T + (kotak.B - kotak.T) * fy)
    local perintah = {}
    for _ = 1, (kali or 1) do
        perintah[#perintah+1] = "input tap " .. x .. " " .. y
    end
    -- digabung jadi SATU panggilan su -- di RedFinger tiap 'su' makan ~6 detik
    sh("su -c '" .. table.concat(perintah, "; sleep 0.4; ") .. " 2>&1'")
    return { x = x, y = y, kotak = kotak }
end

-- v4.90: jalanin perintah yang butuh waktu lama. sh() dipatok 8 detik (sengaja,
-- biar 'su' yang hang gak nahan worker), jadi buat rekam sentuhan perlu jalur
-- sendiri.
function jalan_lama(cmd, detik)
    local h = io.popen("timeout " .. (detik or 30) .. " " .. cmd .. " 2>/dev/null")
    if not h then return "" end
    local o = h:read("*all") or ""
    h:close()
    return o
end

-- v4.90: REKAM SENTUHAN. Daripada nebak-geser angka, lebih enak: user pencet
-- sendiri tombolnya, worker nyatet koordinatnya.
-- Jebakannya: getevent ngasih koordinat PANEL sentuh (arah aslinya, portrait),
-- sedangkan layar RF dikunci landscape -- jadi sumbunya keputar. Daripada nebak
-- rumus putarannya, dicoba KEEMPAT kemungkinan, terus dipilih yang jatuh DI
-- DALAM kotak jendela client. Cara ini benerin dirinya sendiri.
-- v4.91: ukuran layar APA ADANYA (gak dituker walau landscape). Panel sentuh
-- lapornya dalam arah fisik, jadi pembaginya harus yang ini -- bukan
-- layar_ukuran() yang udah dituker buat landscape.
function layar_fisik()
    local o = sh("su -c 'wm size'") or ""
    local w, h = o:match("Override size:%s*(%d+)x(%d+)")
    if not w then w, h = o:match("Physical size:%s*(%d+)x(%d+)") end
    return tonumber(w) or 0, tonumber(h) or 0
end


-- v4.98: DAFTAR ARAH YANG MUNGKIN SECARA FISIK.
-- Panel sentuh lapor dalam arah aslinya. Kalau panel TEGAK (720x1280) sedangkan
-- layar REBAH (1280x720), maka "apa adanya" dan "dibalik" MUSTAHIL -- sumbu X
-- panel cuma sampai 720, gak mungkin ngisi lebar layar 1280. Nyisain 2 arah.
-- Dulu keempatnya dicoba, dan yang mustahil sering kepilih (asal jatuh di dalam
-- jendela) -- itu yang bikin hasilnya ngawur pas jendelanya gede.
function arah_calon(maxX, maxY, W, H)
    local bedaArah = ((maxY > maxX) ~= (H > W))
    if bedaArah then
        return {
            { nama = "diputar kanan", x = function(nx, ny) return 1 - ny end,
                                      y = function(nx, ny) return nx end },
            { nama = "diputar kiri",  x = function(nx, ny) return ny end,
                                      y = function(nx, ny) return 1 - nx end },
        }
    end
    return {
        { nama = "apa adanya", x = function(nx, ny) return nx end,
                               y = function(nx, ny) return ny end },
        { nama = "dibalik",    x = function(nx, ny) return 1 - nx end,
                               y = function(nx, ny) return 1 - ny end },
    }
end

-- v5.16: penengah kalau tap-nya ambigu (dua arah sama-sama jatuh di dalam
-- jendela). Cuma kejadian kalau jendelanya hampir sepenuh layar -- di ukuran
-- grid beneran (226x293 / 610x330) risikonya 0%. Patokannya setelan putaran
-- layar Android: rotasi 1 -> "diputar kiri", rotasi 3 -> "diputar kanan".
function arah_dari_rotasi(maxX, maxY, W, H)
    local rot = tonumber((sh("su -c 'settings get system user_rotation'") or ""):match("%d+"))
    if not rot then return nil end
    local calon = arah_calon(maxX, maxY, W, H)
    for _, c in ipairs(calon) do
        if (rot == 1 and c.nama == "diputar kiri")
        or (rot == 3 and c.nama == "diputar kanan")
        or ((rot == 0 or rot == 2) and (c.nama == "apa adanya" or c.nama == "dibalik")) then
            return c, rot
        end
    end
    return nil, rot
end

-- v4.98: KUNCI ARAH pakai patokan. Dikasih satu sentuhan yang SUDAH DIKETAHUI
-- mestinya jatuh di mana (mis. tengah jendela), dipilih arah yang hasilnya
-- paling dekat ke situ. Sekali terkunci, dipakai buat semua sentuhan berikutnya
-- -- gak ada tebak-tebakan per sentuhan lagi.
function kunci_arah(sx, sy, maxX, maxY, W, H, sasX, sasY)
    local nx, ny = sx / maxX, sy / maxY
    local juara, jarakJuara
    for _, c in ipairs(arah_calon(maxX, maxY, W, H)) do
        local X, Y = c.x(nx, ny) * W, c.y(nx, ny) * H
        local d = math.sqrt((X - sasX) ^ 2 + (Y - sasY) ^ 2)
        if not jarakJuara or d < jarakJuara then juara, jarakJuara = c, d end
    end
    return juara, jarakJuara
end

-- v4.97: ubah SATU sentuhan mentah jadi titik layar + pecahan jendela.
-- v4.98: kalau 'arah' dikasih, pakai itu (udah terkunci). Kalau nggak, jatuh ke
-- cara lama: coba yang mungkin, ambil yang jatuh di dalam kotak.
function sentuh_ke_pecahan(sx, sy, maxX, maxY, W, H, kotak, arah)
    local snx, sny = sx / maxX, sy / maxY
    local coba = arah and { arah } or arah_calon(maxX, maxY, W, H)
    for _, c in ipairs(coba) do
        local X, Y = c.x(snx, sny) * W, c.y(snx, sny) * H
        local didalam = (X >= kotak.L and X <= kotak.R and Y >= kotak.T and Y <= kotak.B)
        if arah or didalam then
            return { X = math.floor(X), Y = math.floor(Y), cara = c.nama, didalam = didalam,
                     fx = (X - kotak.L) / (kotak.R - kotak.L),
                     fy = (Y - kotak.T) / (kotak.B - kotak.T) }
        end
    end
    return nil
end

function rekam_sentuh(pkg, kotak, detik)
    local berkas = "/sdcard/velium_ev.txt"
    sh_silent("su -c 'rm -f " .. berkas .. "'")
    jalan_lama("su -c 'timeout " .. (detik or 30) .. " getevent -l > " .. berkas .. "'",
               (detik or 30) + 8)
    local isi = sh("su -c 'cat " .. berkas .. " 2>/dev/null'") or ""
    sh_silent("su -c 'rm -f " .. berkas .. "'")
    if not isi:match("%S") then return nil, "gak ada kejadian kerekam (getevent gagal?)" end

    -- ambil pasangan X/Y TERAKHIR
    -- v4.95: KUMPULIN SEMUA sentuhan, bukan cuma satu.
    -- Dulu diambil yang pertama -- tapi gerakan PINDAH ke jendela client itu
    -- sendiri kecatat sebagai sentuhan, dan itu yang keambil (padahal bukan
    -- tombolnya). Sekarang: semua dikumpulin, dipilih yang pertama JATUH DI
    -- DALAM kotak jendela. Jadi mencet berkali-kali pun aman -- pencetan yang
    -- di luar jendela (pindah aplikasi, browser) kesaring sendiri.
    local xs, ys = {}, {}
    for nilai in isi:gmatch("ABS_MT_POSITION_X%s+(%x+)") do xs[#xs+1] = tonumber(nilai, 16) end
    for nilai in isi:gmatch("ABS_MT_POSITION_Y%s+(%x+)") do ys[#ys+1] = tonumber(nilai, 16) end
    if #xs == 0 then
        for nilai in isi:gmatch("ABS_X%s+(%x+)") do xs[#xs+1] = tonumber(nilai, 16) end
        for nilai in isi:gmatch("ABS_Y%s+(%x+)") do ys[#ys+1] = tonumber(nilai, 16) end
    end
    local px, py = xs[1], ys[1]
    -- v4.93: dijaga SEBELUM diubah. Dulu langsung tonumber(nil,16) -> meledak,
    -- padahal ini keadaan wajar (kelamaan mencet / kelewat waktunya).
    if not px or not py then
        -- bedain "gak kepencet" vs "getevent-nya emang gak ngerekam apa-apa"
        local nBaris = 0
        for _ in isi:gmatch("\n") do nBaris = nBaris + 1 end
        local adaSentuh = isi:find("BTN_TOUCH", 1, true) ~= nil
        if nBaris <= 5 then
            return nil, "getevent gak ngerekam apa-apa (" .. nBaris .. " baris) -- root/izinnya?"
        elseif adaSentuh then
            return nil, "ada sentuhan kerekam tapi koordinatnya gak kebaca (format lain?)"
        end
        return nil, "gak ada sentuhan dalam " .. (detik or 30) ..
                    " detik (" .. nBaris .. " baris kerekam) -- kelewat waktunya?"
    end
    -- v4.96: JANGAN di-tonumber lagi di sini. Sejak v4.95 nilainya udah diubah
    -- jadi bilangan pas dikumpulin ke xs/ys -- konversi kedua bikin error
    -- ("string expected, got number"). Baris pemeriksaan dobel juga dibuang.

    -- batas panel sentuh (buat ngubah ke ukuran layar)
    local prop = sh("su -c 'getevent -p 2>&1'") or ""
    local maxX, maxY
    for a, b in prop:gmatch("0035%s*:%s*value %d+, min %d+, max (%d+)()") do maxX = tonumber(a) end
    for a in prop:gmatch("0036%s*:%s*value %d+, min %d+, max (%d+)") do maxY = tonumber(a) end

    local W, H = layar_ukuran()          -- layar tampilan (udah dituker kalau landscape)
    local fW, fH = layar_fisik()         -- panel sentuh (arah fisik, gak dituker)
    if not maxX or maxX <= 0 then maxX = (fW > 0) and fW or W end
    if not maxY or maxY <= 0 then maxY = (fH > 0) and fH or H end

    -- v4.95: coba tiap sentuhan (urut), tiap arah -- ambil yang pertama jatuh
    -- di dalam kotak jendela.
    for i = 1, math.min(#xs, #ys) do
        local sx, sy = xs[i], ys[i]
        local snx, sny = sx / maxX, sy / maxY
        local arah = {
            { nama = "apa adanya",    x = snx,     y = sny },
            { nama = "diputar kanan", x = 1 - sny, y = snx },
            { nama = "diputar kiri",  x = sny,     y = 1 - snx },
            { nama = "dibalik",       x = 1 - snx, y = 1 - sny },
        }
        for _, c in ipairs(arah) do
            local X, Y = c.x * W, c.y * H
            if X >= kotak.L and X <= kotak.R and Y >= kotak.T and Y <= kotak.B then
                return { fx = (X - kotak.L) / (kotak.R - kotak.L),
                         fy = (Y - kotak.T) / (kotak.B - kotak.T),
                         X = math.floor(X), Y = math.floor(Y),
                         cara = c.nama, mentahX = sx, mentahY = sy,
                         keBerapa = i, total = math.min(#xs, #ys) }
            end
        end
    end
    return nil, (math.min(#xs, #ys) .. " sentuhan kerekam, tapi GAK ADA yang jatuh " ..
                 "di kotak jendela [" .. kotak.L .. "," .. kotak.T .. "]-[" ..
                 kotak.R .. "," .. kotak.B .. "] -- kepencetnya di luar jendela client?")
end

-- ============================================================
-- v5.00: CARI TOMBOL KEY SENDIRI (nyapu + diverifikasi + diinget)
--
-- Kenapa nyapu, bukan dikalibrasi sekali: layar client GAK BISA diintip sama
-- sekali di RedFinger -- uiautomator nol simpul teks, logcat gak nyatet URL-nya,
-- berkas gak nyimpen. Semua jalur udah dicoba, buntu.
--
-- TAPI keberhasilannya BISA diperiksa: habis mencet, papan klip keisi link key
-- atau nggak. Jawabannya pasti. Jadi worker gak perlu tau tombolnya di mana --
-- dia coba beberapa titik, tiap kali diperiksa, berhenti pas kena.
--
-- Diinget PER UKURAN JENDELA. Worker sendiri yang naruh ukuran jendela (lewat
-- prefs App Cloner), jadi ukurannya terbatas: 4 client sekian, 6 client sekian.
-- Sekali ketemu buat satu ukuran, besoknya langsung tembak -- gak nyapu lagi.
-- Ukuran berubah (ganti jumlah client) -> nyapu sekali lagi, terus diinget juga.
-- ============================================================
TAP_FILE = "velium_tap.txt"

-- titik sapuan. v5.10: gak cuma garis tengah lagi.
-- Awalnya cuma x=0.5 karena tombolnya panjang -- tapi itu berasumsi dialognya
-- pas di tengah jendela. Di jendela sempit, dialognya bisa mepet/kepotong,
-- jadi garis tengah doang bisa gak pernah kena.
-- Sekarang: garis tengah DULU (paling mungkin), baru melebar kiri-kanan.
-- Urutannya sengaja dari yang paling mungkin -- makin cepet ketemu, makin
-- sedikit ronde yang kepakai.
-- v5.12: titik pinggir (0.22 / 0.78) DICABUT. Dari pengamatan lapangan, dialog
-- Delta gak ngisi penuh jendela client -- sisanya tembus pandang, jadi pencetan
-- di situ NEMBUS ke Termux di belakangnya (kelihatan kayak "Roblox masuk
-- background"). Percuma disapu.
-- Gantinya: garis tengah dirapetin (langkah 0,05), soalnya tombolnya panjang --
-- yang perlu dicari cuma TINGGINYA, bukan kiri-kanannya.
-- v5.17: DIBETULIN PAKAI DATA LAPANGAN. Dulu semua titik ada di garis tengah
-- (x=0.5) -- itu asumsi gua bahwa dialognya di tengah jendela. SALAH: hasil
-- kalibrasi manual nunjukin tombolnya di x=0.81, jauh ke kanan. Makanya sapuan
-- lama gak pernah kena, seberapa rapat pun titik Y-nya.
-- Sekarang: kolom kanan (0.81) didahuluin, baru tengah, baru kiri.
-- v5.21: disusun ulang pakai HASIL KALIBRASI NYATA di tiga bentuk grid:
--   1 baris (610x653) -> 0.844 , 0.713
--   2 baris (396x293) -> 0.823 , 0.723
--   3 baris (348x173) -> 0.833 , 0.808
-- X-nya STABIL di ~0.83 semua -- yang geser cuma Y (makin pendek jendelanya,
-- makin ke bawah). Jadi sapuan difokusin di kolom 0.83, Y-nya yang diayak.
TITIK_SAPU = {
    -- kolom 0.83, Y persis di tiga titik yang kebukti dulu
    { 0.83, 0.72 }, { 0.83, 0.81 }, { 0.83, 0.71 },
    -- Y di antara & di luar ketiganya
    { 0.83, 0.76 }, { 0.83, 0.66 }, { 0.83, 0.86 }, { 0.83, 0.61 },
    { 0.83, 0.90 }, { 0.83, 0.56 },
    -- geser kiri-kanan sedikit, kalau-kalau tata letaknya beda
    { 0.75, 0.72 }, { 0.90, 0.72 }, { 0.75, 0.81 }, { 0.90, 0.81 },
    -- garis tengah & kiri: jaring terakhir
    { 0.50, 0.72 }, { 0.50, 0.81 }, { 0.25, 0.72 },
}

function tap_muat()
    -- v6.08: KALIBRASI BAWAAN (inline, gak nambah lokal -- batas 200). Dari
    -- kalibrasi lapangan (velium catat). RF baru langsung punya titik key buat
    -- ukuran umum, gak perlu catat manual. File velium_tap.txt NIMPA bawaan
    -- per-ukuran -> kalibrasi manual per-RF tetep menang.
    --   290x330 = 8 client (4x2) Â· 610x330 = 4 client (2x2) Â· 610x653 = 2 client
    --   396x293 = 2 baris Â· 348x173 = 3 baris
    local t = {
        ["290x330"] = { fx = 0.819, fy = 0.686 },   -- 8 client (4x2)
        ["610x330"] = { fx = 0.830, fy = 0.681 },   -- 4 client (2x2)
        ["610x653"] = { fx = 0.844, fy = 0.713 },   -- 2 client (1 baris)
        ["396x293"] = { fx = 0.823, fy = 0.723 },   -- 2 baris
        ["348x173"] = { fx = 0.833, fy = 0.808 },   -- 3 baris
        ["226x293"] = { fx = 0.853, fy = 0.668 },   -- 10 client (5x2) v7.68 (tested KENA)
        ["226x330"] = { fx = 0.853, fy = 0.668 },   -- 10 client (5x2) v7.68 (tested KENA)
        ["396x330"] = { fx = 0.833, fy = 0.675 },   -- 6 client (3x2) v8.94 (velium catat, rata2 14 titik)
    }
    -- v7.53: JANGAN baca velium_tap.txt lagi (user minta). Dulu file NIMPA bawaan
    -- (kalibrasi manual per-RF menang), TAPI velium catat gampang salah pencet ->
    -- kesimpen X ngaco (mis. 226x293 -> 0.661 harusnya 0.819). Sekarang PAKAI
    -- BAWAAN AJA (X stabil ~0.82, udah kebukti). velium_tap.txt diabaikan total.
    return t
end

function tap_simpan(kunci, fx, fy)
    local t = tap_muat()
    t[kunci] = { fx = fx, fy = fy }
    local f = io.open(TAP_FILE, "w")
    if not f then return false end
    for k, v in pairs(t) do
        f:write(("%s %.3f %.3f\n"):format(k, v.fx, v.fy))
    end
    f:close()
    return true
end

-- Android 10+ cuma ngizinin baca papan klip kalau aplikasinya LAGI DI DEPAN.
-- Jadi Termux dimunculin sebentar, dibaca, terus balik lagi ke client.
function baca_klip()
    sh_silent("su -c 'am start -n com.termux/com.termux.app.TermuxActivity'")
    os.execute("sleep 2")
    local h = io.popen("timeout 10 termux-clipboard-get 2>/dev/null")
    local isi = h and (h:read("*all") or "") or ""
    if h then h:close() end
    return (isi:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- link key yang sah? (jangan ketipu sisa salinan lama)
function klip_link_key(isi)
    if not isi or isi == "" then return nil end
    local link = isi:match("(https?://[^%s\"']+)")
    if not link then return nil end
    if link:find("platorelay", 1, true) or link:find("?d=", 1, true)
       or link:find("&d=", 1, true) then
        return link
    end
    return nil
end

-- balikin: link, fx, fy, keterangan
function cari_tombol_key(cfg, pkg)
    local kotak, sebab = jendela_kotak(pkg)
    if not kotak then return nil, nil, nil, "gagal baca kotak jendela: " .. tostring(sebab) end
    local lebar  = kotak.R - kotak.L
    local tinggi = kotak.B - kotak.T
    local kunci  = ("%dx%d"):format(lebar, tinggi)

    -- kosongin papan klip dulu, biar sisa salinan lama gak dikira berhasil
    os.execute("printf '' | timeout 10 termux-clipboard-set >/dev/null 2>&1")

    -- urutan coba: yang UDAH KEINGET buat ukuran ini duluan, baru sapuan
    local urut = {}
    local tebakX, tebakY = nil, nil   -- v5.47: tebakan dari jumlah baris grid
    local adaKalibrasi = false
    local inget = tap_muat()[kunci]
    -- v9.59: TOLERANSI Â±8px. Bug user: ukuran window 290x327 gak match "290x330"
    -- (beda 3px, App Cloner kadang geser dikit) -> gak nemu kalibrasi -> tebak
    -- nyasar. Cari ukuran TERDEKAT di tabel (dalam 8px lebar & tinggi) -> pakai
    -- kalibrasi itu. Ukuran udah kita tau: 610x330=4, 396x330=6, 290x330=8,
    -- 226x330=10 client. Titik nyesuain ukuran aktual (yg user minta).
    if not inget then
        local tabel = tap_muat()
        local beda_terkecil = 9
        for uk, titik in pairs(tabel) do
            local w, h = uk:match("(%d+)x(%d+)")
            w, h = tonumber(w), tonumber(h)
            if w and h then
                local dw, dh = math.abs(w - lebar), math.abs(h - tinggi)
                if dw <= 8 and dh <= 8 and (dw + dh) < beda_terkecil then
                    beda_terkecil = dw + dh
                    inget = titik
                end
            end
        end
        if inget then
            info(("    ukuran %s ~ kalibrasi terdekat (beda %dpx) -> pakai titik itu"):format(kunci, beda_terkecil))
        end
    end
    -- v9.60: FALLBACK MATEMATIS. Kalau gak ada exact match + gak ada yg deket 8px,
    -- HITUNG titik dari interpolasi. User: worker sesuain titik pakai matematika
    -- buat ukuran BARU. fx stabil ~0.836 (rata2 semua kalibrasi). fy tergantung
    -- TINGGI window (makin pendek jendela, tombol makin ke bawah) -> interpolasi
    -- linear dari anchor: 173px->0.808, 293->0.723, 330->0.675, 653->0.713.
    if not inget then
        local anchor = {
            {h = 173, fy = 0.808}, {h = 293, fy = 0.723},
            {h = 330, fy = 0.675}, {h = 653, fy = 0.713},
        }
        local fyHit
        if tinggi <= anchor[1].h then fyHit = anchor[1].fy
        elseif tinggi >= anchor[#anchor].h then fyHit = anchor[#anchor].fy
        else
            for i = 1, #anchor - 1 do
                if tinggi >= anchor[i].h and tinggi <= anchor[i+1].h then
                    local t = (tinggi - anchor[i].h) / (anchor[i+1].h - anchor[i].h)
                    fyHit = anchor[i].fy + t * (anchor[i+1].fy - anchor[i].fy)
                    break
                end
            end
        end
        if fyHit then
            inget = { fx = 0.836, fy = fyHit }
            info(("    ukuran %s BARU -> titik dihitung matematis (fx=0.836 fy=%.3f)"):format(kunci, fyHit))
        end
    end
    if inget then
        -- v8.78: ukuran ini UDAH DIKALIBRASI (tested KENA, misal 226x293 = 10
        -- client -> 0.853,0.668). Titik ini PASTI kena. User minta konsisten:
        -- ULANG titik yang SAMA 10x, JANGAN sapu titik lain (yg melesat). Dialog
        -- kadang belum settle di tap pertama -> ulang di titik yg sama sampai kena.
        adaKalibrasi = true
        for _ = 1, 10 do
            urut[#urut+1] = { inget.fx, inget.fy, ingetan = true }
        end
    end

    -- v5.47: kalau ukuran ini BELUM pernah dikalibrasi, tebak dari JUMLAH BARIS
    -- grid. Data lapangan nunjukin yang nentuin posisi tombol itu jumlah BARIS,
    -- bukan jumlah client -- dialog Delta ukurannya tetap, jadi makin pendek
    -- jendelanya, makin ke bawah tombolnya:
    --   1 baris -> Y 0.713    2 baris -> Y 0.723    3 baris -> Y 0.808
    -- X-nya stabil ~0.83 di semua. Jadi tebakan ini biasanya kena di percobaan
    -- PERTAMA, bukan setelah nyapu belasan titik.
    if not inget then
        local tinggiLayar = select(2, layar_ukuran())
        if tinggiLayar and tinggiLayar > 0 and tinggi > 0 then
            local baris = math.max(1, math.floor(tinggiLayar / tinggi + 0.5))
            -- v6.07: Y per jumlah baris (dari kalibrasi lapangan user):
            --   1 baris 0.713 Â· 2 baris 0.723 Â· 3 baris 0.808
            -- X SELALU ~0.83 di semua ukuran (temuan user). Jadi tebakan ini
            -- HAMPIR SELALU kena di percobaan pertama -- gak perlu sapu 16 titik.
            -- baris > 3 (jarang) pakai 0.808 (paling bawah). baris gak masuk akal
            -- (0 atau kegedean) tetep kasih tebakan default 2-baris -- daripada
            -- langsung sapu 16 titik dari nol.
            local ty = ({ [1] = 0.713, [2] = 0.723, [3] = 0.808 })[baris]
            if not ty then
                ty = (baris > 3) and 0.808 or 0.723   -- default aman: 2-baris
            end
            tebakX, tebakY = 0.83, ty
            urut[#urut+1] = { tebakX, tebakY, tebakan = baris }
        else
            -- v6.07: gagal ukur layar/jendela -> tetep kasih tebakan default
            -- (X 0.83, Y 0.723 = posisi 2-baris paling umum) daripada sapu nol.
            tebakX, tebakY = 0.83, 0.723
            urut[#urut+1] = { tebakX, tebakY, tebakan = 0 }
        end
        -- v8.77: ULANG titik 1 (tebakan) 8x -- KONSISTEN di titik yang SAMA.
        -- User: titik 1 SELALU kena, titik 2+ (TITIK_SAPU) melesat jauh. Jadi
        -- tap titik 1 berulang (dialog kadang belum settle di tap pertama), gak
        -- lompat ke titik lain. TITIK_SAPU tetep ditambahin di BELAKANG sebagai
        -- cadangan kalau 8x titik 1 bener-bener gagal.
        if tebakX and tebakY then
            for _ = 1, 7 do
                urut[#urut+1] = { tebakX, tebakY, tebakan = -1 }   -- ulang titik 1
            end
        end
    end

    -- v8.78: SKIP sapu titik lain kalau ukuran udah dikalibrasi (titik pasti kena,
    -- diulang 10x di atas). Sapu titik lain cuma buat ukuran yg BELUM dikalibrasi.
    if not adaKalibrasi then
    for _, t in ipairs(TITIK_SAPU) do
        -- v5.47 FIX: bandingin ke tebakan yang DISIMPEN, bukan ke urut[#urut].
        -- Dulu urut[#urut] udah bukan tebakan lagi begitu titik sapuan pertama
        -- masuk -- jadi duplikatnya cuma kesaring di item pertama. Ketangkep
        -- pas uji 3 baris: tebakan 0.808 terus 0.810 nongol lagi.
        local samaIngetan = inget and math.abs(t[1] - inget.fx) < 0.01
                            and math.abs(t[2] - inget.fy) < 0.01
        local samaTebakan = tebakY and math.abs(t[1] - tebakX) < 0.01
                            and math.abs(t[2] - tebakY) < 0.01
        if not samaIngetan and not samaTebakan then
            urut[#urut+1] = { t[1], t[2] }
        end
    end
    end   -- tutup 'if not adaKalibrasi' (v8.78)

    for i, t in ipairs(urut) do
        -- v5.14: bisa DIHENTIKAN. Dulu perintah panjang kayak gini gak pernah
        -- ngecek tanda berhenti -- 'velium stop' cuma nyetop loop worker, dan
        -- Ctrl+C sering gak nyampe kalau lagi nunggu 'su'. Jadi sapuan yang
        -- lagi jalan gak bisa dibatalin sama sekali.
        if ada_stop() then
            return nil, nil, nil, "dihentikan (velium stop)"
        end
        -- v5.08: client HARUS beneran di depan sebelum ditembak. Ronde
        -- sebelumnya mindahin fokus ke Termux buat baca papan klip, dan Termux
        -- itu layar penuh -- nutupin jendela client yang ngambang.
        -- v6.13: pastikan_depan DIBUANG. tap_jendela ukur fresh + cek fokus
        -- SENDIRI sebelum tap -- kalau client gak di depan (Termux nyelonong),
        -- tap BATAL sendiri. Gak perlu paksa-depan (yang goyangin fokus).
        io.write(("\r   titik %d/%d  (%.2f, %.2f) ...          "):format(i, #urut, t[1], t[2]))
        io.flush()
        -- v7.57: JEDA SEBELUM TAP = 15 detik (user minta). Kasih waktu jendela +
        -- dialog key bener-bener settle sebelum tap (biar gak keburu-buru pas
        -- dialog belum pas / masih loading). Bisa dibatalin di tengah.
        -- v8.77: titik ULANG (tebakan=-1) jeda lebih pendek (5s) -- dialog udah
        -- settle dari tap pertama, gak perlu nunggu 15s tiap ulang.
        local jedaTap = (t.tebakan == -1) and 5 or 15
        for _ = 1, jedaTap do
            if ada_stop() then return nil, nil, nil, "dihentikan (velium stop)" end
            os.execute("sleep 1")
        end
        local tok, tsebab = tap_jendela(cfg, pkg, t[1], t[2], 2)   -- ukur fresh sendiri
        if not tok then
            -- tap dibatalin tap_jendela (fullscreen / Termux di depan / gagal ukur).
            -- JANGAN tap nyasar. Catat & lanjut -- putaran sapu berikut (di bypass)
            -- udah cek grafis + settle petak, jadi client dibenerin di situ.
            io.write("\n")
            info("  tap batal: " .. tostring(tsebab))
            -- kasih jeda dikit, jangan langsung hajar titik berikut
            os.execute("sleep 3")
        else
            -- v7.56: jeda setelah tap dinaikin (kasih waktu "Copied link" +
            -- clipboard kebaca sebelum cek klip).
            os.execute("sleep 3")
        end

        local link = klip_link_key(baca_klip())
        if link then
            tap_simpan(kunci, t[1], t[2])
            return link, t[1], t[2],
                   (t.ingetan and "pakai ingatan" or ("ketemu di percobaan ke-" .. i))
                   .. " (" .. kunci .. ")"
        end
    end

    return nil, nil, nil, ("dicoba " .. #urut .. " titik di jendela " .. kunci ..
                           ", papan klip tetep kosong")
end

function config_set_bypass(apikey)
    local f = io.open(CONFIG_FILE, "r")
    if not f then
        return false, "config gak ada -- jalanin `velium` dulu buat setup"
    end
    local isi = f:read("*all") or ""
    f:close()

    local baris = string.format('  bypass_api_key=%q,', apikey)
    local baru
    if isi:find("bypass_api_key%s*=") then
        -- ganti yang lama, SATU baris utuh (pakai fungsi, biar '%' di kunci
        -- gak dianggap kode pengganti)
        baru = isi:gsub('[ \t]*bypass_api_key%s*=%s*"[^"]*"[ \t]*,?[ \t]*\r?\n?',
                        function() return baris .. "\n" end, 1)
    else
        -- sisipin sebelum '}' penutup
        local pos = isi:match("^.*()}")
        if not pos then return false, "bentuk config gak dikenali" end
        baru = isi:sub(1, pos - 1) .. baris .. "\n" .. isi:sub(pos)
    end

    -- === DITES DI MEMORI DULU ===
    local uji = load("return " .. baru)
    if not uji then
        return false, "hasil editan gak sah -- config LAMA GAK DISENTUH"
    end
    local sah, hasil = pcall(uji)
    if not sah or type(hasil) ~= "table" then
        return false, "hasil editan gak sah -- config LAMA GAK DISENTUH"
    end
    if (hasil.bypass_api_key or "") ~= apikey then
        return false, "kunci gak kebaca balik -- config LAMA GAK DISENTUH"
    end

    -- cadangan dulu, biar ada jalan pulang kalau ada apa-apa
    local bak = io.open(CONFIG_FILE .. ".bak", "w")
    if bak then bak:write(isi); bak:close() end

    local g = io.open(CONFIG_FILE, "w")
    if not g then return false, "gak bisa nulis config (izin?)" end
    g:write(baru)
    g:close()
    return true
end

-- ============================================================
-- v4.2: BISA DIMATIIN
-- Dulu satu-satunya cara berhenti itu `pkill -f velium_worker.lua` â€” mati
-- mendadak: notif nyangkut, wake-lock kepegang, panel gak tau dia mati.
--
-- Lua polos gak bisa nangkep sinyal (kill/Ctrl+C) tanpa luaposix, jadi
-- dipake FLAG FILE: `stop` bikin file, loop utama ngecek tiap putaran,
-- terus keluar baik-baik.
-- ============================================================

function tulis_pid()
    local pid = tonumber(sh("echo $PPID")) or 0
    local f = io.open(PID_FILE, "w")
    if f then f:write(tostring(pid)); f:close() end
    return pid
end

function baca_pid()
    local f = io.open(PID_FILE, "r"); if not f then return nil end
    local p = tonumber(f:read("*l")); f:close(); return p
end

function pid_hidup(pid)
    if not pid then return false end
    return sh("ps -p " .. pid .. " -o comm=") ~= ""
end


function hapus(f) os.remove(f) end

-- dipanggil pas keluar baik-baik: beresin semua yang nyangkut
-- v9.83: cek RF SIAP di-reboot -- Termux:Boot kepasang + boot script ada.
-- GLOBAL (bukan local) biar gak makan slot 200 lokal main chunk.
function boot_siap()
    local RUMAH = os.getenv("HOME") or "/data/data/com.termux/files/home"
    -- 1) boot script ada?
    local f = io.open(RUMAH .. "/.termux/boot/velium", "r")
    if not f then
        return false, "boot script ~/.termux/boot/velium GAK ADA (jalanin: velium pasang)"
    end
    f:close()
    -- 2) app Termux:Boot kepasang? (cek folder data / pm list)
    local ada = sh("su -c 'pm list packages com.termux.boot 2>/dev/null' 2>/dev/null") or ""
    if not ada:find("com.termux.boot") then
        -- fallback cek folder data
        local ada2 = sh("su -c 'ls -d /data/data/com.termux.boot 2>/dev/null' 2>/dev/null") or ""
        if not ada2:find("com.termux.boot") then
            return false, "app Termux:Boot BELUM kepasang (install dari F-Droid + buka sekali)"
        end
    end
    return true, ""
end

function bersih(cfg, sebab)
    print()
    info("Beres-beres (" .. (sebab or "?") .. ")...")
    sh_silent("termux-notification-remove velium_worker")
    sh_silent("termux-wake-unlock")
    hapus(PID_FILE)
    hapus(STOP_FILE)
    shell_matikan()   -- v4.70: tutup shell root tetap + bersihin pipa
    ok("Worker berhenti.")
end

-- ============================================================
-- API â€” Cloudflare Worker
-- ============================================================
-- ============================================================
-- v5.74: PILIH ALAT HTTP -- curl ATAU wget.
--
-- Kenapa perlu: curl di Termux gampang rusak gara-gara upgrade setengah jalan.
-- Yang kejadian di lapangan:
--   CANNOT LINK EXECUTABLE ".../curl": cannot locate symbol
--   "SSL_set_quic_tls_transport_params" referenced by "libngtcp2_crypto_ossl.so"
-- Itu libngtcp2 (dukungan HTTP/3) dibangun buat OpenSSL yang lebih baru dari
-- yang kepasang. Akibatnya curl mati TOTAL.
--
-- Dan curl itu satu-satunya jalan worker ngomong ke panel -- jadi satu paket
-- rusak bikin seluruh RF diem. Itu titik gagal tunggal yang gak perlu ada:
-- wget hampir selalu ada di Termux dan gak kena masalah yang sama.
--
-- Dicek SEKALI di awal, hasilnya diinget. Bukan tiap permintaan -- itu boros
-- dan hasilnya gak bakal berubah di tengah jalan.
-- ============================================================
-- Ditempel ke RIW (tabel yang udah ada), BUKAN lokal baru: Lua batesin 200
-- lokal per fungsi utama dan file ini udah mepet -- nambah satu bikin gagal
-- compile. Namanya RIW.http biar jelas ini kelompok lain.
-- ============================================================
-- v5.77 FIX: `RIW` dideklarasi DI SINI, sebelum dipakai.
--
-- Dulu deklarasinya di bawah (dekat catat_riwayat) sementara RIW.http diisi
-- di atas -- jadi pas dijalanin: "attempt to index a nil value (global 'RIW')"
-- dan worker MATI TOTAL di baris pertama.
--
-- Kenapa lolos: penyisir urutan-deklarasi cuma nyari PEMANGGILAN FUNGSI
-- (`nama(`), gak nyari PENGAKSESAN TABEL (`nama.field`). Dua-duanya kena
-- masalah yang sama, tapi cuma satu yang dicek.
--
-- Satu tabel buat dua kelompok (riwayat + http) SENGAJA: Lua batesin 200 lokal
-- per fungsi utama dan file ini udah mepet -- nambah lokal baru bikin gagal
-- compile.
-- ============================================================
RIW = {
    file = (os.getenv("HOME") or ".") .. "/velium_riwayat.log",
    maks = 2000,
}

RIW.http = { alat = nil }

function RIW.http.pilih()
    if RIW.http.alat then return RIW.http.alat end
    -- curl dites BENERAN JALAN, bukan cuma "ada berkasnya". Kasus di atas
    -- persisnya begitu: berkasnya ada, `command -v` nemu, tapi begitu
    -- dijalanin langsung gagal link.
    local uji = io.popen("curl --version 2>&1")
    local out = uji and uji:read("*all") or ""
    if uji then uji:close() end
    if out:find("curl %d") then RIW.http.alat = "curl"
    else
        local u2 = io.popen("wget --version 2>&1")
        local o2 = u2 and u2:read("*all") or ""
        if u2 then u2:close() end
        if o2:find("Wget") or o2:find("wget") then RIW.http.alat = "wget"
        else RIW.http.alat = "curl" end   -- gak ada dua-duanya: tetep curl biar
                                       -- pesan errornya keliatan, bukan diem
    end
    return RIW.http.alat
end

-- GET. Balikin perintah shell-nya, biar pemanggil tetep pakai sh() yang sama.
function RIW.http.get_cmd(kunci, alamat, detik)
    detik = detik or 10
    if RIW.http.pilih() == "wget" then
        return string.format("wget -qO- -4 --timeout=%d --header=%s %s",
            detik, shq("X-Kunci: " .. kunci), shq(alamat))
    end
    return string.format("curl -s -4 -m %d -H %s %s",
        detik, shq("X-Kunci: " .. kunci), shq(alamat))
end

function RIW.http.kirim_cmd(kunci, alamat, metode, berkas, detik)
    detik = detik or 10
    if RIW.http.pilih() == "wget" then
        -- wget: PUT/DELETE lewat --method (butuh wget yang agak baru).
        -- --body-file buat kirim isi berkas.
        -- v9.40: header X-Panel-Versi=worker -> backend kecualiin worker dari guard
        -- versi panel (guard cuma buat panel lama, bukan worker).
        return string.format(
            "wget -qO- -4 --timeout=%d --method=%s --header=%s --header=%s --header=%s --body-file=%s %s",
            detik, metode, shq("X-Kunci: " .. kunci),
            shq("X-Panel-Versi: worker"),
            shq("Content-Type: application/json"), berkas, shq(alamat))
    end
    return string.format("curl -s -4 -m %d -X %s -H %s -H %s -H %s -d @%s %s",
        detik, metode, shq("X-Kunci: " .. kunci),
        shq("X-Panel-Versi: worker"),
        shq("Content-Type: application/json"), berkas, shq(alamat))
end

TMP = "/data/data/com.termux/files/usr/tmp/velium_body.json"

function api_get(cfg, jalur)
    return sh(RIW.http.get_cmd(cfg.kunci, cfg.url .. jalur, 10))
end

-- v5.39: metode bisa dipilih (bawaan POST, biar pemakaian lama gak berubah).
-- Perlu karena /perintah minta PUT -- dan tanpa ini setup gak bisa nyetel
-- perintah awal sendiri.
function api_post(cfg, jalur, body, metode)
    local f = io.open(TMP, "w")
    if not f then TMP = "./velium_body.json"; f = io.open(TMP, "w") end
    if not f then return "" end
    f:write(body); f:close()
    return sh(RIW.http.kirim_cmd(cfg.kunci, cfg.url .. jalur,
                             metode or "POST", TMP, 10))
end

-- JSON kecil doang, cukup pola. gak perlu library.
function ambil_str(js, k) return tostring(js or ""):match('"'..k..'"%s*:%s*"(.-)"') end
function ambil_num(js, k) return tonumber(tostring(js or ""):match('"'..k..'"%s*:%s*(-?%d+)')) end
-- v4.32: escape LENGKAP. Dulu cuma \ dan " -- baris baru/tab dari output shell
-- lolos mentah ke JSON -> laporan RUSAK -> Cloudflare nolak -> panel kira worker
-- MATI padahal jalan. Sekarang semua karakter kontrol ikut di-escape.
function jstr(s)
    s = tostring(s or ""):gsub('\\','\\\\'):gsub('"','\\"')
    s = s:gsub('\n','\n'):gsub('\r','\\r'):gsub('\t','\\t')
    s = s:gsub('%c', ' ')   -- sisa karakter kontrol lain -> spasi
    return '"'..s..'"'
end

-- v9.69: ada_perintah_baru dipindah KE SINI (setelah api_get + ambil_str
-- didefinisiin). Bug user: dulu di baris ~1269 -> api_get masih nil (local
-- didefinisiin di 2113) -> worker crash "attempt to call nil value api_get".
-- Cek ada perintah NYELA (PAKSA/RESTART/STANDBY/STOP/CLOSE) beda dari yg lagi
-- jalan. Buat NYELA loop panjang. Throttle 2s (cache) biar gak spam API.
function ada_perintah_baru(cfg, isiLagiJalan)
    if ada_stop() then return true end
    local skrg = os.time()
    if (skrg - _apb_waktu) < 2 then return _apb_cache end
    _apb_waktu = skrg
    local r = api_get(cfg, "/perintah?tim=" .. cfg.tim)
    local isi = (ambil_str(r, "isi") or "")
    local u = isi:upper()
    local nyela = false
    if u:find("STANDBY") or u:find("STOP") or u:find("CLOSE") or u:find("TEMBAK") or u:find("REBOOT") or u:find("UPDATE") or u:find("DOWNLOAD") then nyela = true
    elseif (u:find("PAKSA") or u:find("RESTART")) and isi ~= (isiLagiJalan or "") then
        -- v9.77 FIX LOOP: RESTART/PAKSA cuma nyela kalau ts-nya BARU (belum diproses).
        -- Bug: RESTART netep di DB -> nyela terus tiap 2s -> loop selamanya.
        local tsR = ambil_num(r, "ts") or 0
        if tsR ~= (RESTART_TS_PROSES or 0) then nyela = true end
    elseif u:find("ROTASI%-GO") then
        -- v9.198: ROTASI-GO (stock restock) = PRIORITAS -> NYELA loop biar borong
        -- cepet, gak nunggu rejoin/denyut kelar (~35s). User: rotasi langsung, abaikan
        -- yg lagi jalan. Dedup pakai ts (nyela sekali per sinyal, gak loop).
        local tsR = ambil_num(r, "ts") or 0
        if tsR ~= (ROTASI_GO_TS_PROSES or 0) then nyela = true; ROTASI_GO_TS_PROSES = tsR end
    elseif u:find("ROTASI") and not u:find("ROTASI%-GO") and not u:find("ROTASI%-TEST") then
        -- v9.165 FIX LOOP: ROTASI (toggle on/off) DULU nyela TANPA cek ts -> sticky
        -- di DB -> nyela terus tiap 2s -> rejoin/loop panjang GAK PERNAH KELAR.
        -- Sekarang cuma nyela sekali (ts baru), sama kayak PAKSA/RESTART.
        local tsR = ambil_num(r, "ts") or 0
        if tsR ~= (ROTASI_TS_PROSES or 0) then nyela = true; ROTASI_TS_PROSES = tsR end
    end
    if nyela then
        info("<< PERINTAH PANEL MASUK: " .. isi:sub(1, 40) .. " -- STOP loop, urus ini >>")
    end
    _apb_cache = nyela
    return nyela
end

-- v9.199: tulis /perintah TAPI JAGA ROTASI-GO. Kalau ada ROTASI-GO yg BELUM diproses
-- (isi != ROTASI_GO_LAST), JANGAN nimpa -- biar sinyal restock gak ilang ketimpa FORCE
-- yg worker tulis sendiri. User curiga ROTASI-GO ke-block/ketimpa. Ini nutup celah itu.
function tulis_perintah_jaga(cfg, bodyJson)
    local r = api_get(cfg, "/perintah?tim=" .. cfg.tim)
    local nowIsi = ambil_str(r, "isi") or ""
    if nowIsi:upper():find("ROTASI%-GO") and nowIsi ~= ROTASI_GO_LAST then
        info("[jaga] ada ROTASI-GO belum diproses -> SKIP tulis FORCE (biar rotasi gak ilang)")
        return false
    end
    return api_post(cfg, "/perintah", bodyJson, "PUT")
end

-- v9.201: cek ada ROTASI-GO BARU (beda dari yg lagi diproses ROTASI_GO_LAST). Dipake
-- pas rotasi LAGI JALAN -> kalau ada stock baru, abort & ulang buat yg baru (utamain).
function ada_rotasi_go_baru(cfg, seedSkrg)
    local r = api_get(cfg, "/perintah?tim=" .. cfg.tim)
    local isi = ambil_str(r, "isi") or ""
    if not (isi:upper():find("ROTASI%-GO") ~= nil and isi ~= ROTASI_GO_LAST) then return false end
    -- v9.203: cuma abort kalau seed BEDA. Seed SAMA (restock lagi) = JANGAN abort --
    -- biar rotasi gak muter-muter (spam) buat seed yg sering restock (mis.
    -- super_watering_can, gear common ~5 menit sedangkan rotasi ~8 menit).
    local seedBaru = isi:match("ROTASI%-GO|([^|]*)|")
    if seedBaru and seedSkrg and seedBaru == seedSkrg then return false end
    return true
end

-- ============================================================
-- v5.31: KUNCI API bypass DIAMBIL DARI PANEL kalau config kosong.
--
-- Dulu ditanyain di SETIAP setup RF. 20 RF = 20 kali ngetik kunci yang sama,
-- dan tiap salah ketik = `velium key` gagal tanpa sebab yang jelas.
--
-- Sekarang urutannya:
--   1. config lokal (kalau diisi manual, itu yang menang -- bisa beda per RF)
--   2. panel (/bypass-key) -- diisi SEKALI di sana, semua RF kebagian
-- Hasil dari panel di-cache di memori; kalau panel mati, yang udah kepegang
-- tetep kepakai sampai worker restart.
--
-- Tetep GAK masuk GitHub: kuncinya ada di D1, bukan di berkas yang di-push.
-- ============================================================
BYPASS_CACHE, BYPASS_CACHE_TS = nil, 0

ambil_apikey = function(cfg)
    -- 1. config lokal MENANG -- buat RF yang sengaja dikasih kunci beda
    --    (`velium key set <APIKEY>`)
    local lokal = cfg and cfg.bypass_api_key or ""
    if lokal ~= "" then return lokal, "config" end

    -- 2. bawaan yang ditaruh di file ini. Dipakai LANGSUNG -- gak nanya panel,
    --    jadi nol delay dan gak bergantung panel idup apa nggak.
    if BYPASS_KEY_BAWAAN ~= "" then return BYPASS_KEY_BAWAAN, "bawaan" end

    -- 3. panel -- cuma kepakai kalau BYPASS_KEY_BAWAAN dikosongin
    --    (mis. repo dijadiin publik)
    -- cache masih segar (10 menit) -> pakai itu
    if BYPASS_CACHE and BYPASS_CACHE ~= "" and (os.time() - BYPASS_CACHE_TS) < 600 then
        return BYPASS_CACHE, "panel (cache)"
    end

    local r = api_get(cfg, "/bypass-key") or ""
    if r ~= "" then
        local k = ambil_str(r, "key")
        if k and k ~= "" then
            BYPASS_CACHE, BYPASS_CACHE_TS = k, os.time()
            -- v5.32: SIMPEN KE CONFIG LOKAL. Sekali narik, habis itu gak
            -- pernah butuh panel lagi -- instan, dan tetep jalan walau panel
            -- lagi mati pas lisensi Delta abis (itu justru saat paling
            -- genting). Ini yang bikin gak perlu ngetik manual TANPA harus
            -- naruh kunci di berkas yang di-push ke GitHub.
            if cfg then
                cfg.bypass_api_key = k
                local okS = pcall(function() save_config(cfg) end)
                if okS then ok("Kunci API disimpen ke config RF ini -- gak narik dari panel lagi.") end
            end
            return k, "panel"
        end
        -- endpoint ada tapi kuncinya belum diisi
        if not ambil_str(r, "error") then return "", "panel (kosong)" end
    end
    -- panel gak jawab tapi cache lama masih ada -> lebih baik dipakai
    if BYPASS_CACHE and BYPASS_CACHE ~= "" then
        return BYPASS_CACHE, "panel (cache lama)"
    end
    return "", "gak ada"
end


-- ============================================================
-- deteksi client
-- ============================================================
-- v4.34: JALAN DARURAT. Kalau penanda "ActivityNativeMain" gak cocok lagi
-- (Roblox ganti nama activity / bentuk dumpsys beda), client kebaca OFF terus
-- padahal game jalan. Set deteksi_longgar=true di config -> cukup "ada
-- ActivityRecord" dianggap jalan. Efek samping: Roblox yang nyangkut di Home
-- ikut kebaca "jalan". Bridge (/stat) tetep jadi penentu sebenernya.
DETEKSI_LONGGAR = false
-- v4.36: Roblox GANTI NAMA activity. Dulu cuma dikenal "ActivityNativeMain";
-- di Roblox baru namanya "com.roblox.client.startup.MainGameActivity". Worker
-- nyari nama lama -> gak pernah ketemu -> client SELALU kebaca off padahal
-- game jalan normal. Sekarang dua-duanya (plus varian *GameActivity) dikenal.
PENANDA_GAME = { "ActivityNativeMain", "MainGameActivity" }

function pkg_running(pkg)
    -- "beneran DI GAME" -- bukan cuma "ada ActivityRecord" (Home Roblox,
    -- key system, splash JUGA punya ActivityRecord tapi BUKAN di game).
    local o = sh("su -c 'dumpsys activity activities | grep ActivityRecord | grep " .. pkg .. "'")
    for line in o:gmatch("[^\n]+") do
        if line:find(pkg, 1, true) then
            for _, tanda in ipairs(PENANDA_GAME) do
                if line:find(tanda, 1, true) then return true end
            end
        end
    end
    -- v4.34: mode longgar -> ada ActivityRecord buat paket ini = dianggap jalan
    if DETEKSI_LONGGAR then
        for line in o:gmatch("[^\n]+") do
            if line:find(pkg, 1, true) then return true end
        end
    end
    return false
end

-- v4.29: ID device -- dipakai buat "1 tim = 1 RedFinger".
-- android_id nempel per-device & gak berubah kecuali factory reset.
DEV_ID_CACHE = nil
-- v4.63: cek status SEMUA client dari SATU dump. Dulu pkg_running dipanggil
-- per client -- tiap panggilan 'su' di RedFinger ~6 detik, jadi 4 client = ~24
-- detik. Padahal ini jalan tiap 10 detik -> worker lebih banyak nunggu su
-- daripada kerja, dan perintah panel jadi telat dieksekusi.
-- v5.45: sekalian ngecek PROSES (pidof), bukan cuma jendela (dumpsys).
-- Dua-duanya digabung ke SATU panggilan su, jadi gak nambah ongkos.
--
-- Kenapa perlu dibedain: client bisa PROSESNYA IDUP tapi JENDELANYA GAK ADA
-- (jalan di latar / jendelanya keburu dilepas). Dulu keadaan itu ditampilin
-- "off" -- padahal beda jauh artinya:
--   off   = mati total, tinggal dibuka
--   latar = prosesnya masih idup, HARUS ditutup dulu sebelum dibuka
--           ('am start' ke proses yang idup itu NO-OP -- dia nangkring di
--            server lama dan gak pernah pindah walau linknya udah ganti)
-- Gara-gara sama-sama ditulis "off", log "tutup paksa" keliatan gak masuk akal.
-- Balikin: hasil[p] = ada jendela?, hidup[p] = prosesnya idup?
function pkg_running_semua(pkgs)
    local hasil, hidup = {}, {}
    for _, p in ipairs(pkgs) do hasil[p] = false; hidup[p] = false end

    local bagian = { "dumpsys activity activities | grep ActivityRecord" }
    for _, p in ipairs(pkgs) do
        bagian[#bagian+1] = 'echo "@PID ' .. p .. ' $(pidof ' .. p .. ')"'
    end
    local o = sh_tmo("su -c '" .. table.concat(bagian, "; ") .. "'", #pkgs + 15) or ""

    for baris in o:gmatch("[^\r\n]+") do
        local pkgPid, pidnya = baris:match("^@PID%s+(%S+)%s*(.*)$")
        if pkgPid then
            if tostring(pidnya):match("%d") then hidup[pkgPid] = true end
        else
            for _, p in ipairs(pkgs) do
                if not hasil[p] and baris:find(p, 1, true) then
                    for _, tanda in ipairs(PENANDA_GAME) do
                        if baris:find(tanda, 1, true) then hasil[p] = true break end
                    end
                    if DETEKSI_LONGGAR then hasil[p] = true end
                end
            end
        end
    end
    return hasil, hidup
end

function dev_id()
    if DEV_ID_CACHE then return DEV_ID_CACHE end
    local id = (sh("su -c 'settings get secure android_id'") or ""):match("%w+")
    if not id or id == "null" or #id < 4 then
        id = (sh("su -c 'getprop ro.serialno'") or ""):match("%S+")
    end
    if not id or id == "" or id == "unknown" then
        id = "rf-" .. tostring(os.time())   -- terakhir banget: acak sekali
    end
    DEV_ID_CACHE = id
    return id
end

-- v6.00: nama device buat panel. GLOBAL (bukan local) biar gak kena batas 200
-- lokal Lua -- file worker udah mentok. Cache di KICK_DIURUS.
function devnama_now()
    if KICK_DIURUS["_devnama"] then return KICK_DIURUS["_devnama"] end
    local brand = (sh("su -c 'getprop ro.product.brand' 2>/dev/null") or ""):match("[%w ]+") or ""
    local model = (sh("su -c 'getprop ro.product.model' 2>/dev/null") or ""):match("[%w %-_]+") or ""
    brand = brand:gsub("%s+$", ""); model = model:gsub("%s+$", "")
    local nama
    if brand ~= "" and model ~= "" then
        nama = brand:sub(1,1):upper() .. brand:sub(2) .. " " .. model
    elseif model ~= "" then nama = model
    elseif brand ~= "" then nama = brand
    else nama = "RedFinger" end
    KICK_DIURUS["_devnama"] = nama
    return nama
end

-- v9.76: banner header COKLAT KARAMEL (versi + device + id device). border kotak rapi.
-- (banner_karamel DIHAPUS -- box-drawing mojibake di Termux; banner_velium yg kepakai)

-- ============================================================
-- BANNER STARTUP "VELIUM PANEL" (kuning, ASCII only, sekali pas nyala).
-- Render FIGlet LIVE (`figlet -f 3-d`, VELIUM/PANEL ditumpuk biar muat layar
-- HP). SATU warna (\27[1;33m kuning terang), reset tiap baris. Font 3-d
-- ASCII murni -> gak mojibake di Termux. Font 3-d gak dikenal -> font bawaan
-- figlet; figlet GAK ADA -> teks polos tengah. Gak pernah error, gak kepotong.
-- BUTUH (sekali): `pkg install figlet` -- pasang otomatis buat RF baru.
-- Dipanggil sekali via pcall di run() -> banner GAK BISA gagalkan start.
-- ============================================================
BANNER_FONTFIG = "3-d"
function banner_velium()
    local Y, N = "\27[1;33m", "\27[0m"
    -- lebar terminal: $COLUMNS dulu, baru stty, mentok 80. Dibatasi 200
    -- biar string.rep gak bisa makan memori kalau nilainya ngaco.
    local w = tonumber(os.getenv("COLUMNS")) or 0
    if w <= 0 then
        local h = io.popen("stty size 2>/dev/null")
        if h then
            w = tonumber((h:read("*all") or ""):match("%d+%s+(%d+)")) or 0
            h:close()
        end
    end
    if w <= 0 then w = 80 end
    if w > 200 then w = 200 end
    -- ambil 1 kata dari figlet. Balikin tabel baris, atau nil kalau figlet
    -- gak ada / font gak dikenal (keluaran kosong).
    local function ambil(kata, font)
        local cmd = "figlet -w 200 " .. (font and ("-f " .. font .. " ") or "")
                    .. kata .. " 2>/dev/null"
        local h = io.popen(cmd)
        if not h then return nil end
        local o = h:read("*all") or ""
        h:close()
        if not o:match("%S") then return nil end
        local t = {}
        for line in (o .. "\n"):gmatch("(.-)\n") do t[#t + 1] = line end
        return t
    end
    -- font yg kepakai: 3-d dulu, kalau gak dikenal -> bawaan figlet
    local a1 = ambil("VELIUM", BANNER_FONTFIG)
    local fontPakai = BANNER_FONTFIG
    if not a1 then a1, fontPakai = ambil("VELIUM", nil), nil end
    local art = nil
    if a1 then
        local a2 = ambil("PANEL", fontPakai)
        if a2 then
            art = a1
            art[#art + 1] = ""
            for _, line in ipairs(a2) do art[#art + 1] = line end
        end
    end
    -- ukur lebar blok (tanpa spasi ekor)
    local full = 0
    if art then
        for i, line in ipairs(art) do
            art[i] = line:gsub("%s+$", "")
            if #art[i] > full then full = #art[i] end
        end
    end
    -- figlet gak ada / sempit -> teks polos tengah (tetap kuning, gak kepotong)
    if not art or full == 0 or full > w then
        local teks = "VELIUM PANEL"
        local pad = math.max(0, math.floor((w - #teks) / 2))
        io.write("\n" .. Y .. string.rep(" ", pad) .. teks .. N .. "\n\n")
        io.flush()
        return
    end
    -- blok dirata: semua baris mulai di kolom yg sama, bloknya di-tengah
    io.write("\n")
    for _, line in ipairs(art) do
        if line == "" then
            io.write("\n")   -- baris kosong: tanpa spasi ekor
        else
            local pad = math.max(0, math.floor((w - full) / 2))
            io.write(Y .. string.rep(" ", pad) .. line
                     .. string.rep(" ", full - #line) .. N .. "\n")
        end
    end
    io.write("\n")
    io.flush()
end

-- ============================================================
-- v4.17: konfirmasi BENERAN di game lewat bridge (/stat)
-- Home Roblox = ActivityNativeMain JUGA -> pkg_running gak bisa bedain Home
-- vs in-game. Yg beneran nandain di dalam game + script jalan = akun LAPOR
-- ke /stat (bridge cuma denyut dari dalam game). Sama persis kayak auto-rejoin.
-- ============================================================
KONFIRMASI_POLL = 3    -- poll /stat tiap brp detik pas nungguin masuk game
-- v4.60 FIX: dulu 45 detik -- padahal script cuma lapor tiap 120 detik kalau
-- gak ada perubahan. Akibatnya client SEHAT sering keliatan basi -> gak dilewat
-- -> DIBUNUH & DIBUKA ULANG percuma, terus ditungguin lapor lagi. Itu yang bikin
-- kerasa "nunggu lama padahal client udah aman".
-- Sekarang 200 detik: lebih longgar dari jarak lapor (120) + toleransi CPU 100%.
-- v4.68: dari 200 -> 300. Script lapor tiap 120 detik, TAPI pas CPU 100% loop
-- script molor bisa 2x -> laporan nyatanya tiap ~240 detik. Ambang 200 nyisain
-- jarak cuma 80 detik: sekali molor, client SEHAT keliatan basi terus ditutup &
-- dibuka ulang percuma. 300 ngasih toleransi 1,5x jarak lapor.
FRESH_WINDOW    = 300  -- akun "masih di game" kalau lapor <= sekian detik lalu

-- ambil ts (kapan terakhir akun lapor) dari string /stat
function bridge_ts(stat, akun)
    if not stat or not akun then return nil end
    local blok = stat:match('{[^{}]-"nama"%s*:%s*"' .. akun .. '"[^{}]-}')
    return blok and tonumber(blok:match('"ts"%s*:%s*(%d+)')) or nil
end

-- true kalau akun lapor fresh (masih beneran di game SEKARANG)
function bridge_fresh(stat, akun)
    local ts = bridge_ts(stat, akun)
    -- v4.53 FIX: "skrg" di /stat itu ANGKA, tapi dulu dibaca pakai ambil_str
    -- (khusus teks berkutip) -> SELALU nil -> fungsi ini SELALU balik false.
    -- Akibatnya: semua client kebaca "beku", dan skip-check di open_all gak
    -- pernah kena (client yang udah jalan tetep dibuka ulang).
    local skrg = ambil_num(stat, "skrg")
    if not ts or not skrg then return false end
    return (skrg - ts) <= FRESH_WINDOW
end

-- tungguin akun lapor BARU (ts > ts0) -> tanda script mulai jalan -> BENERAN masuk game.
-- ts0 = ts sebelum client dibuka (bisa nil kalau belum pernah lapor).
-- return true kalau kedeteksi masuk, false kalau timeout / dibatalin.
-- v4.42: dideklarasi di depan -- tunggu_bridge perlu manggil ini, padahal
-- definisinya jauh di bawah (butuh build_url dll).
cek_layar = nil

INTIP_DETIK = 30   -- v4.42: kapan mulai ngintip layar (detik)
INTIP_ULANG = 10   -- v4.44: jeda sebelum cek ULANG (mastiin beneran nyangkut)
function tunggu_bridge(cfg, akun, ts0, batas, cek_batal, pkg, mapLink)
    local mulai = os.time()
    local sudahIntip = false
    -- v4.41: kalau client MASIH di layar game, kasih perpanjangan. Pas CPU 100%
    -- rantai "load game -> Delta inject -> script jalan -> lapor pertama" bisa
    -- lewat 90 detik. Dulu langsung divonis nyangkut -> client SEHAT dibunuh ->
    -- ngulang dari nol -> makin lama. Sekarang: selama masih di layar game,
    -- ditungguin (maks 2x batas). Kalau kelempar dari game, langsung nyerah.
    local batasMax = batas * 2
    while (os.time() - mulai) < batasMax do
        if cek_batal and cek_batal() then return false end
        local ts = bridge_ts(api_get(cfg, "/stat"), akun)
        if ts and (not ts0 or ts > ts0) then return true end
        -- v4.42: jangan cuma nungguin bridge diem sampai 90 detik baru sadar.
        -- Setelah INTIP_DETIK, lihat layarnya sekali: kalau nyangkut di Home /
        -- popup umur / ada error, langsung ketauan -- gak usah nunggu penuh.
        if (not sudahIntip) and (os.time() - mulai) >= INTIP_DETIK and pkg and cek_layar then
            sudahIntip = true
            local pesan, sifat, sidik1 = cek_layar(cfg, pkg, mapLink)
            if pesan and (sifat == "home" or sifat == "manual" or sifat == "ulang") then
                -- v4.44: JANGAN langsung divonis. Kadang beberapa detik kemudian
                -- dia lanjut masuk game sendiri (Home cuma numpang lewat).
                os.execute("sleep " .. INTIP_ULANG)
                local ts2 = bridge_ts(api_get(cfg, "/stat"), akun)
                if ts2 and (not ts0 or ts2 > ts0) then return true end   -- ternyata masuk
                local pesan2, sifat2, sidik2 = cek_layar(cfg, pkg, mapLink)
                if pesan2 then
                    -- Home / popup umur / error: itu layar DIEM, gak bakal lanjut
                    -- sendiri -> langsung vonis.
                    if sifat2 == "home" or sifat2 == "manual" or (pesan2:find("Error", 1, true)) then
                        return false, pesan2
                    end
                    -- Loading / layar kosong: cuma dianggap BEKU kalau layarnya
                    -- GAK BERUBAH. Kalau berubah, berarti masih jalan (loading
                    -- berat) -> jangan dibunuh, lanjut ditungguin.
                    if sidik1 and sidik2 and sidik1 == sidik2 then
                        return false, pesan2 .. " (layar gak gerak)"
                    end
                end
                -- udah gak nyangkut / masih gerak -> lanjut nungguin bridge kayak biasa
            end
        end
        if (os.time() - mulai) >= batas then
            -- lewat batas normal: cuma lanjut kalau masih di layar game
            if not (pkg and pkg_running(pkg)) then return false end
        end
        os.execute("sleep " .. KONFIRMASI_POLL)
    end
    return false
end

-- ============================================================
-- v4.18: orientasi layar RF + keep-alive (anti-FC)
-- ============================================================
-- kunci orientasi RF. "landscape"/"portrait" -> set, "" / nil -> jangan disenggol.
-- user_rotation: 0=portrait, 1=landscape, 2=portrait kebalik, 3=landscape kebalik.
function set_orientasi(cfg)
    local o = (cfg.orientasi or ""):lower()
    if o ~= "landscape" and o ~= "portrait" then return end
    local rot = (o == "landscape") and 1 or 0
    sh("su -c 'settings put system accelerometer_rotation 0 >/dev/null 2>&1; " ..
       "settings put system user_rotation " .. rot .. " >/dev/null 2>&1'")
end

-- keep-alive / anti-FC. bikin client Roblox lebih tahan idup di background:
--   * deviceidle whitelist        -> lepas dari Doze
--   * appops RUN_IN_BACKGROUND     -> boleh jalan di background
--   * oom_score_adj rendah         -> OOM killer segan bunuh
-- Android suka RESET oom_score_adj balik -> makanya di-apply ULANG tiap ~menit.
-- PENTING: worker (Termux) dilindungin LEBIH kuat dari client. jadi kalau RAM
-- mentok, yg dikorbanin CLIENT (bisa di-rejoin), BUKAN worker (biar tetep mantau).
OOM_CLIENT = -300   -- client: dilindungin, tapi masih bisa dikorbanin kalau kepepet
OOM_WORKER = -800   -- worker: dilindungin lebih kuat, jangan sampe ke-kill
-- v4.62: SATU panggilan su buat SEMUA paket. Tiap 'su -c' di RedFinger makan
-- ~5 detik; dulu dipanggil per-paket (4 client = 5 panggilan = ~25 detik cuma
-- buat keep-alive). Sekarang digabung -> sekali jalan.
function keep_alive_apply(cfg)
    if cfg.keep_alive == false then return end
    local bagian = {}
    for _, pkg in ipairs(split(cfg.pkgs)) do
        bagian[#bagian+1] = string.format(
            "dumpsys deviceidle whitelist +%s >/dev/null 2>&1; " ..
            "cmd appops set %s RUN_IN_BACKGROUND allow >/dev/null 2>&1; " ..
            "for p in $(pidof %s); do echo %d > /proc/$p/oom_score_adj 2>/dev/null; done",
            pkg, pkg, pkg, OOM_CLIENT)
    end
    -- lindungin worker sendiri LEBIH kuat (Termux app + proses worker ini)
    local wpid = baca_pid() or ""
    bagian[#bagian+1] = string.format(
        "dumpsys deviceidle whitelist +com.termux >/dev/null 2>&1; " ..
        "for p in $(pidof com.termux) %s; do echo %d > /proc/$p/oom_score_adj 2>/dev/null; done",
        wpid, OOM_WORKER)
    sh("su -c '" .. table.concat(bagian, "; ") .. "'")
end

-- ============================================================
-- buka Roblox
-- ============================================================
-- v4.83: JATAH BUNUH per client. Tanpa ini, client yang masalahnya emang GAK
-- bisa diselesaiin restart (link PS mati, akun kena limit, key belum masuk)
-- bakal dibunuh-buka terus tiap ronde: boros RAM, bikin client lain ikut
-- kesenggol, dan gak pernah kelar. Lewat jatah -> berhenti nyentuh, catet aja
-- biar keliatan di panel dan bisa dibenerin manual.
KILL_CATAT  = {}
KILL_MAKS   = 3      -- maks sekian kali bunuh...
KILL_JENDELA = 1800  -- ...dalam sekian detik (30 menit) per client

-- ============================================================
-- v5.73: CATATAN KEJADIAN KE BERKAS -- buat DIAGNOSA, bukan buat dibaca live.
--
-- Kenapa perlu: log yang ada cuma 6 baris terakhir di memori. Jadi pertanyaan
-- macam "267-nya kejadian SETELAH rejoin, atau sendiri?" dan "berapa kali
-- rejoin per jam?" GAK BISA DIJAWAB -- dan tanpa itu, tiap perbaikan cuma
-- tebakan. (Termasuk tebakan gua sendiri di v5.71: gua bikin rejoin instan
-- pas 267 tanpa tau gag2 v6.5 udah pernah nyoba dan buang pendekatan itu.)
--
-- Yang dicatet SENGAJA cuma kejadian yang jarang: rejoin, kick, buka/tutup.
-- Status rutin TIDAK dicatet -- kalau semua dicatet, berkasnya gede dan yang
-- penting ketimbun.
--
-- Berkasnya dibatesin ~2000 baris (dipangkas dari depan). Ini alat diagnosa,
-- bukan pembukuan -- yang dibutuhin pola beberapa jam terakhir.
-- ============================================================

function RIW.catat(jenis, akun, ket)
    pcall(function()
        local f = io.open(RIW.file, "a")
        if not f then return end
        f:write(string.format("%d\t%s\t%s\t%s\t%s\n",
            os.time(), os.date("%Y-%m-%d %H:%M:%S"),
            tostring(jenis), tostring(akun or "-"), tostring(ket or "")))
        f:close()
    end)
    -- pangkas kalau kegedean. Dicek jarang (1 dari ~50 tulisan) biar gak baca
    -- seluruh berkas tiap kali nyatet.
    if math.random(50) == 1 then
        pcall(function()
            local f = io.open(RIW.file, "r")
            if not f then return end
            local baris = {}
            for l in f:lines() do baris[#baris+1] = l end
            f:close()
            if #baris <= RIW.maks then return end
            local g = io.open(RIW.file, "w")
            if not g then return end
            for i = #baris - RIW.maks + 1, #baris do g:write(baris[i], "\n") end
            g:close()
        end)
    end
end

function sisa_jatah_kill(pkg)
    local skrg, sisa = os.time(), {}
    for _, w in ipairs(KILL_CATAT[pkg] or {}) do
        if (skrg - w) < KILL_JENDELA then sisa[#sisa+1] = w end
    end
    KILL_CATAT[pkg] = sisa
    return KILL_MAKS - #sisa
end

function catat_kill(pkg)
    KILL_CATAT[pkg] = KILL_CATAT[pkg] or {}
    table.insert(KILL_CATAT[pkg], os.time())
end

DEBUG_OPEN = false

function build_url(cfg, link_client)
    -- v4.11: link PS PER-CLIENT (dari assign-ps panel). urutan prioritas:
    --   1. link_client (assign per akun dari panel) -- kalau dikasih
    --   2. cfg._ps_override (PS tim dari panel, lama)
    --   3. cfg.link_code (diketik di Termux)
    -- v9.74: paksa PUBLIC HANYA kalau server mode dari panel = PUBLIC (dropdown
    -- server "w2-public"). Bug user: mau PRIVATE tapi masuk public. Sebab: v9.72
    -- paksa public kalau _ps_override=="" -- TAPI _ps_override="" itu dari /ps
    -- endpoint KOSONG (gak ada PS tim manual), BUKAN berarti mau public. Sekarang
    -- cek SERVER_TERAKHIR (field server dari setting-tim): cuma "public" yg maksa.
    local serverMode = (SERVER_TERAKHIR or ""):lower()
    if serverMode:find("public") then
        -- panel pilih server PUBLIC -> gak pakai PS apapun (link_client/override)
        return "roblox://placeId=" .. cfg.place_id
    end
    -- v9.97: SERVER CUSTOM -> semua akun ke SATU server yg SAMA (link custom lo).
    -- Pakai _ps_override (link dari /ps) DULUAN, ABAIKAN link_client (getps per-akun
    -- yg accessCode-nya beda tiap akun). User sengaja set 1 link -> semua harus kesitu.
    local lc
    if serverMode == "custom" and cfg._ps_override and cfg._ps_override ~= "" then
        lc = cfg._ps_override
    else
        lc = link_client
        if lc == nil or lc == "" then lc = cfg._ps_override end
        if lc == nil then lc = cfg.link_code or "" end
    end
    lc = lc or ""
    -- v9.182: kalau ada _ps_override = privateServerLinkCode (UNIVERSE-level, kepake
    -- lintas dunia -- tinggal ganti placeId), PAKE ITU walau ada link_client (accessCode
    -- getps yg PLACE-SPECIFIC -> nyangkut dunia lama pas ganti dunia). Insight user:
    -- link privateServerLinkCode SAMA lintas dunia, cuma ganti id game. accessCode
    -- kepaku ke server 1 place -> gak bisa dipindah dunia.
    if cfg._ps_override and cfg._ps_override:find("privateServerLinkCode") then
        lc = cfg._ps_override
    end
    -- v4.16: LINK SHARE MODERN (share?code=XXX&type=Server) -> code itu BUKAN
    -- linkCode! itu kode share yg harus di-RESOLVE Roblox dulu. dulu worker
    -- ambil code jadi linkCode langsung -> SALAH -> join gagal, nyangkut server
    -- lama. FIX: buka URL share-nya LANGSUNG, biar Roblox sendiri yg resolve+join.
    if lc:find("share%?code=") or lc:find("/share%?") then
        -- pastikan pakai https lengkap, biar am start buka lewat Roblox app
        if lc:sub(1,4) ~= "http" then lc = "https://www.roblox.com/" .. lc:gsub("^/", "") end
        return lc   -- buka URL share apa adanya -> Roblox resolve sendiri
    elseif lc:find("privateServerLinkCode=") and lc:sub(1,4) == "http" then
        -- v9.181: ganti placeId ke cfg.place_id (dunia AKTIF) -- joinCode universe-level.
        -- v9.185: DEEP LINK roblox://...&linkCode= biar AUTO-JOIN (https URL cuma buka
        -- HALAMAN GAME -> nyangkut Home, gak masuk). Komentar lama bilang linkCode
        -- ditolak "no permission" -- itu dulu buat server ORANG LAIN. Sekarang tiap akun
        -- server SENDIRI (owner) -> boleh join. placeId ikut dunia = universe-level.
        local code = lc:match("privateServerLinkCode=([^&%s]+)")
        return code and ("roblox://placeId="..cfg.place_id.."&linkCode="..code) or lc
    elseif lc:find("accessCode=") then
        -- v7.36: PRIVATE SERVER via accessCode (dari velium getps -- API Roblox
        -- private-servers). Format: "accessCode=UUID". Join langsung ke PS akun.
        local code = lc:match("accessCode=([%w%-]+)")
        return code and ("roblox://placeId=" .. cfg.place_id .. "&accessCode=" .. code) or lc
    elseif lc:find("privateServerLinkCode=") then
        -- format lama (code doang, bukan full URL): bikin full URL biar Roblox
        -- resolve sendiri (bukan roblox:// yg ditolak).
        local code = lc:match("privateServerLinkCode=([^&]+)")
        return code and ("https://www.roblox.com/games/"..cfg.place_id.."/x?privateServerLinkCode="..code) or lc
    elseif lc:sub(1,4)=="http" then return lc
    elseif lc~="" then return "roblox://placeId="..cfg.place_id.."&linkCode="..lc
    else return "roblox://placeId="..cfg.place_id end
end

-- v4.1: FREEFORM
-- Pencet ikon di RedFinger = LAUNCHER yang naro Roblox di freeform.
-- `am start` NGELEWATIN launcher -> kebuka fullscreen. Makanya mesti
-- diminta sendiri lewat --windowingMode.
--   5 = freeform (jendela ngambang, bisa digeser)  <- yang dicari
--   6 = multi-window (jalur Android 12+)
--   0 = jangan minta apa-apa (kayak v4.0)
WIN_OK = nil   -- nil=belum dites, true=didukung, false=ditolak

function open_one(cfg, pkg, link_client, alasan, pakai_S)
    -- v6.64: GUARD CAPTCHA. Kalau client kena captcha (penanda dari cek captcha),
    -- JANGAN rejoin -- percuma, captcha butuh solve manual, rejoin cuma mancing
    -- verif lagi. Semua jalur rejoin lewat sini, jadi cukup dijaga di satu titik.
    if KICK_DIURUS["captcha:" .. pkg] then
        return   -- di-skip, nunggu user solve manual
    end
    -- v8.93: SET GRID posisi SEBELUM buka (semua jalur open_one otomatis kebagian).
    -- Bug user: sebagian client grid gak keatur -- karena banyak jalur open_one
    -- (ganti-akun/mati-mendadak/nudge/dll) buka client TANPA grid_satu dulu ->
    -- posisi lama/default. Taruh di sini (1 titik, semua jalur lewat) -> gak ada
    -- yg kelewat. App Cloner baca prefs pas app MULAI, jadi tulis dulu baru buka.
    -- KECUALI bypass: posisi 10-client udah diatur khusus (petaK) sebelum open_one
    -- -> jangan ketimpa grid biasa (3x2). Titik kalibrasi bypass butuh 10-layout.
    if alasan ~= "start-bypass" then
        pcall(function() grid_satu(cfg, pkg) end)
    end
    -- v7.34: LOG SETIAP REJOIN dengan ALASAN yang jelas (label dari pemanggil,
    -- gak ngandelin traceback yg suka salah). Tiap jalur open_one kasih `alasan`.
    -- `velium rejoin-log` nampilin ringkasan per alasan -> langsung ketauan jalur
    -- mana yang bikin rejoin bareng/sering. alasan nil = "start/buka-awal".
    do
        local al = alasan or "start"
        pcall(function()
            local nama = pkg:gsub("com%.roblox%.", "")
            local f = io.open("/sdcard/velium_rejoin.log", "a")
            if f then
                f:write(string.format("%s | %s | %s\n", os.date("%H:%M:%S"), nama, al))
                f:close()
            end
        end)
    end
    local url = build_url(cfg, link_client)
    -- v8.51: LOG url join (biar keliatan pakai link PS apa public). Kalau ada
    -- privateServerLinkCode -> PS. Kalau cuma placeId -> public.
    do
        local jenisJoin = url:find("privateServerLinkCode") and "PS-fall"
            or (url:find("linkCode") and "PS-linkcode")
            or (url:find("accessCode") and "PS-access")
            or "PUBLIC"
        info(("   [join] %s -> %s | url=%s"):format(
            pkg:gsub("com%.roblox%.",""), jenisJoin, url))
    end
    local wm = tonumber(cfg.win_mode) or 0

    -- v8.09: HAPUS TASK DULU sebelum tembak (user minta). Cuma `am task remove`
    -- task Roblox pkg INI -- BUKAN force-stop (force-stop ngerusak client lain,
    -- lihat v8.08). am task remove cuma buang window/activity task, proses + App
    -- Cloner service GAK disentuh -> client lain aman. Terus jeda 5s biar task
    -- beneran kelar dibuang sebelum tembak masuk (fresh, gak nyangkut task lama).
    -- Tetep NEW_TASK (0x10000000, one task) -- BUKAN A3/multi task.
    -- v9.286: SKIP task-remove buat ARCEUS. User tes manual: cara WC (am start web
    -- URL + CLEAR_TOP 0x14000000) TANPA task-remove BISA join/ganti server, window
    -- GAK ilang (gak keliatan "nutup 1 client dulu"). task-remove + sleep 5s bikin
    -- window ilang bentar. Buat arceus -> murni WC tembak, gak buang window.
    if cfg.executor ~= "arceus" then
    do
        pcall(function()
            local stk = sh("su -c 'am stack list 2>/dev/null'") or ""
            local cari = 1
            local dihapus = false
            while true do
                local _, b = stk:find("taskId=", cari, true)
                if not b then break end
                local nomor = stk:match("^(%d+)", b + 1)
                -- cek blok sekitar taskId ini ada pkg-nya (task punya pkg ini)
                if nomor and stk:sub(b, b + 250):find(pkg, 1, true) then
                    sh_silent("su -c 'am task remove " .. nomor .. " 2>/dev/null'")
                    dihapus = true
                end
                cari = b + 1
            end
            if dihapus then
                os.execute("sleep 5")   -- jeda 5s: task kelar dibuang sebelum tembak
            end
        end)
    end
    end

    local function coba(pakai_wm)
        -- v9.286: ARCEUS -> PAKSA cara WC (web URL + CLEAR_TOP 0x14000000), BUKAN -S.
        -- User tes manual: WC bisa join/ganti server tanpa nutup window. -S kadang
        -- masih goyangin. Walau caller minta pakai_S, buat arceus tetep WC.
        if cfg.executor == "arceus" then pakai_S = false end
        -- v7.85: CARA PANDORA PERSIS (dari logcat: START {dat=... flg=0x10000000
        -- pkg=com.roblox.clienX cmp=.../ActivityProtocolLaunch} from uid 0).
        -- Persis kayak Pandora:
        --   1. -p pkg DAN -n cmp BARENG (routing pasti ke package + activity)
        --   2. flag 0x10000000 = NEW_TASK doang (BUKAN MULTIPLE_TASK -- itu bikin
        --      task numpuk / kadang gak masuk. Pandora TANPA MULTIPLE_TASK)
        --   3. cmp ActivityProtocolLaunch (activity join)
        -- Isolasi Pandora BUKAN dari MULTIPLE_TASK, tapi dari -p+-n+cmp yg bener.
        -- v8.05: pakai_S -> tambah -S (STOP ACTIVITY dulu, start fresh). Ini cara
        -- HIP HUB (dari intip ps-ef: am start -S ...) yang AMAN + selalu masuk.
        -- -S cuma stop ACTIVITY (bukan force-stop app + service), jadi client
        -- nyangkut Home bisa di-restart TANPA goyangin App Cloner service (gak
        -- ngerusak client lain kayak force-stop). Buat client keras kepala.
        local inner
        if pakai_S then
            -- v8.07: kalau -S -> pakai CARA HIP HUB PERSIS (dari ps-ef):
            --   am start -S -a VIEW -d URL -p pkg
            -- CUMA -p pkg. TANPA -n cmp, TANPA flag. -S + -n cmp (yg kita pakai
            -- sebelumnya) ternyata masih bikin client lain FF/keluar. Hip Hub
            -- -S + -p DOANG (Android routing sendiri) = aman. Tiru persis.
            inner = "am start -S -a android.intent.action.VIEW -d '"..url.."' -p "..pkg
        else
            -- v8.10: CARA WC (JACKPOT). Web URL + NEW_TASK|CLEAR_TOP (0x14000000),
            -- TANPA -S, TANPA force-stop. Terbukti: masuk game + bisa rejoin DARI
            -- DALAM game, client lain AMAN (gak keluar). Deep link roblox:// nyangkut
            -- Home; web URL + CLEAR_TOP nge-reset activity Home tanpa stop app.
            -- Konversi ke web URL inline (gak bikin fungsi baru -- batas 200 lokal):
            local pid_w = cfg.place_id or "129343810645058"
            local url_web
            if url:find("share%?code=") or url:find("/share%?") then
                url_web = url   -- link share -> pakai apa adanya (udah http)
            elseif url:find("privateServerLinkCode=") then
                -- v8.51: link PS fall (privateServerLinkCode) -> PAKAI APA ADANYA.
                -- JANGAN konversi ke accessCode (itu format BEDA -> Roblox tolak
                -- "no permission"). URL https lengkap = persis link manual (works).
                url_web = url:sub(1,4) == "http" and url
                    or ("https://www.roblox.com/games/"..pid_w.."/x?"..url:match("(privateServerLinkCode=[%w]+)"))
            else
                local kode_w = (url:match("accessCode=([%w%-]+)")
                    or url:match("linkCode=([%w%-]+)")
                    or url:match("code=([%w%-]+)"))
                if kode_w then
                    url_web = "https://www.roblox.com/games/start?placeId="..pid_w.."&accessCode="..kode_w
                else
                    url_web = "https://www.roblox.com/games/start?placeId="..pid_w
                end
            end
            inner = "am start -a android.intent.action.VIEW -d '"..url_web.."'"
                .. " -p "..pkg
                .. " -f 0x14000000"
            if pakai_wm and wm > 0 then
                inner = inner .. " --windowingMode " .. wm
            end
        end
        local cmd = 'su -c "'..inner..'"'
        if DEBUG_OPEN then print("\n"..C.Y.."[DEBUG] "..C.N..cmd) end
        return cmd, sh(cmd)
    end

    if wm == 0 then
        local cmd = coba(false)
        sh_silent(cmd)
        return
    end

    -- sekali doang: cek Android ini nerima --windowingMode apa nggak
    if WIN_OK == nil then
        local _, out = coba(true)
        if out:find("Unknown option") or out:find("Error: Unknown") then
            WIN_OK = false
            warn("Android ini gak dukung --windowingMode "..wm.." -> balik ke fullscreen")
            warn("Client bakal kebuka fullscreen, bukan freeform.")
        else
            WIN_OK = true
            ok("freeform (mode "..wm..") didukung")
        end
        return   -- percobaan barusan udah kehitung buka
    end

    local cmd = coba(WIN_OK)
    sh_silent(cmd)
end

-- ============================================================
-- v4.1: TUNGGU SAMPAI BENERAN JALAN
-- Dulu: buka -> tidur 4 detik -> lanjut. Gak pernah dicek.
-- Kalau client ke-3 gagal, worker tetep lanjut ke ke-4 kayak gak ada apa-apa,
-- terus lapor "8 client" padahal cuma 7 yang hidup.
--
-- Sekarang: buka -> tungguin muncul -> pastiin gak mati lagi -> baru lanjut.
--
-- CATATAN JUJUR: pgrep cuma tau PROSESNYA muncul, bukan "udah masuk game".
-- Roblox masih butuh ~20-40 detik lagi buat loading. Yang tau beneran udah
-- di kebun cuma star_bridge.lua (dari dalam game) -> keliatan di panel.
-- ============================================================
-- v4.31: prosesnya idup gak? (beda dari pkg_running yg nuntut UDAH DI LAYAR GAME)
function pkg_hidup(pkg)
    return (sh("su -c 'pidof " .. pkg .. "'") or ""):match("%d") ~= nil
end

-- ============================================================
-- v5.57: DETEKSI "UDAH DI DALAM GAME" LEWAT MEMORI GRAFIS.
--
-- Latar: activity Roblox SAMA persis antara halaman awal dan di-dalam-game
-- (v4.36 -- ActivityNativeMain & MainGameActivity itu nama lama vs baru buat
-- activity yang sama), dan teks layar gak kebaca (v4.86). Jadi dulu gak ada
-- cara tau client udah masuk game apa belum -- sapuan tombol key mulai
-- kecepetan, 16 titik kebuang buat dialog yang belum nongol.
--
-- Hasil ukur di lapangan (`velium layar`, RF aMKTN1):
--     Graphics   HOME  15.284 KB   ->   GAME  48.988 KB   (3,2x)
-- Kandidat lain gugur:
--   * jumlah window: 6 vs 6 -- sama. ID-nya emang berubah, tapi itu cuma
--     handle acak, bukan penanda.
--   * UDP/TCP: keukur SE-DEVICE (/proc/net/*), bukan per-client -- kecampur
--     app lain, jadi gak bisa dipercaya.
-- Graphics dari `dumpsys meminfo <pkg>` itu BENERAN per-client.
--
-- Patokannya SENGAJA relatif (kelipatan dari nilai awal), bukan angka mati:
-- memori grafis ikut ukuran jendela. Di RF 10 client petaknya kecil, angkanya
-- pasti lebih rendah dari hasil ukur di atas. Kalau dipatok angka tetap,
-- deteksi bakal salah di RF dengan susunan beda.
-- ============================================================
function grafis_kb(pkg)
    local o = sh("su -c 'dumpsys meminfo " .. pkg .. " 2>/dev/null | grep -i Graphics'") or ""
    -- baris bentuknya: "  Graphics:    48988      ..." -> ambil angka pertama
    local n = o:match("[Gg]raphics:%s*(%d+)")
    return tonumber(n)
end

-- v7.87: cek grafis SEMUA client dalam 1 SU CALL (bukan per-client). su di RF
-- makan ~6s tiap panggil -- 10 client = 60s kalau satu-satu. Gabung ke 1 su
-- (loop di shell), tandain tiap pkg -> parse. Balik map pkg -> KB.
-- Dipakai loop grafis: cek semua sekali, yang <30MB baru diurus.
function grafis_semua(pkgs)
    local hasil = {}
    if #pkgs == 0 then return hasil end
    -- bikin script shell: tiap pkg -> echo "PKG|" + graphics value
    local cmds = {}
    for _, pkg in ipairs(pkgs) do
        -- echo penanda pkg, terus dumpsys grep Graphics
        cmds[#cmds+1] = "echo -n '@@" .. pkg .. "@@'; dumpsys meminfo " .. pkg
            .. " 2>/dev/null | grep -i Graphics | head -1"
    end
    local skrip = table.concat(cmds, "; ")
    local out = sh("su -c \"" .. skrip .. "\"") or ""
    -- parse: tiap baris "@@pkg@@  Graphics:   48988 ..."
    for pkg, angka in out:gmatch("@@(com%.roblox%.[%w_]+)@@%s*[Gg]raphics:%s*(%d+)") do
        hasil[pkg] = tonumber(angka)
    end
    -- pkg yang gak ada Graphics (mati/home <2MB) -> 0
    for _, pkg in ipairs(pkgs) do
        if hasil[pkg] == nil then hasil[pkg] = 0 end
    end
    return hasil
end

-- v7.40: cek client udah MASUK GAME via grafis MB, tungguin sampai BATAS detik.
-- Balik: masuk(true/false), mb(angka MB grafis). Ambang 30 MB (game ~30-49,
-- home ~15, loading <2). Dipakai di loop buka + mati-bareng.
GAME_AMBANG_KB = 25 * 1024   -- v8.13: 30->25 MB. Game map baru kadang stabil
-- di 27-30 MB (dari log: di game 30-56, loading lewat 20-27). Home ~13-19.
-- 25 = di atas Home, nangkep game yg grafisnya pas-pasan. Dulu 30 mepet.
function cek_masuk_game(pkg, batas, cek_batal)
    batas = batas or 20
    local nama = pkg:gsub("com%.roblox%.", "")
    -- v8.11: JANGAN dump berkali-kali (dumpsys meminfo BERAT + su lambat). WC
    -- gacor -> client pasti masuk. Cukup TUNGGU `batas` detik (kasih waktu load),
    -- BARU dump SEKALI di akhir. Cek batal tiap detik biar bisa distop.
    for _ = 1, batas do
        if cek_batal and cek_batal() then return false, 0 end
        os.execute("sleep 1")
    end
    -- dump SEKALI setelah nunggu
    local g = grafis_kb(pkg) or 0
    local mb = g / 1024
    if g >= GAME_AMBANG_KB then
        info(("   %s UDAH DI GAME (grafis %.0f MB)"):format(nama, mb))
        return true, mb
    end
    return false, mb   -- belum masuk (kasih tau MB terakhir)
end

-- v7.59: DETEKSI CAPTCHA via WEBVIEW FD (temuan lapangan). FunCaptcha/Arkose
-- render pakai WebView -> client buka BANYAK file descriptor app_webview. Game
-- normal cuma 0-1. Captcha = 17-18. Ambang 10 (jarak jauh, reliable). Ini GAK
-- pakai uiautomator (lambat) / screenshot (ribet) / grafis (gugur: captcha =
-- background). Cukup hitung fd app_webview di /proc/PID/fd.
-- Balik: true kalau captcha (webview >= ambang), + jumlah webview.
CAPTCHA_WEBVIEW_AMBANG = 10
-- v8.73: cek captcha dari LOGCAT on-demand. Logcat STREAMING dimatiin (v7.51,
-- spam file). Jadi cek pakai `logcat -d` (dump sekali, buffer terakhir) + grep
-- arkose/captcha buat PID client ini. Ringan (1 command, gak streaming terus).
-- Balik true kalau ada event arkose/funcaptcha/captcha di log terakhir client ini.
function cek_captcha_logcat(pkg)
    -- ambil PID client
    local pid = sh("su -c 'pidof " .. pkg .. "' 2>/dev/null") or ""
    pid = pid:match("%d+")
    if not pid then return false end
    -- dump logcat buffer terakhir, filter PID client + kata captcha.
    -- -d = dump & keluar (gak streaming). -t 500 = 500 baris terakhir (cukup).
    local out = sh(("su -c 'logcat -d -t 500 2>/dev/null | grep -i -E \"arkose|funcaptcha|captcha|challenge-container|bot verification\" | grep \" %s \"'"):format(pid)) or ""
    return out:match("%S") ~= nil
end
function cek_captcha_webview(pkg)
    -- ambil PID dulu
    local pid = sh("su -c 'pidof " .. pkg .. "' 2>/dev/null") or ""
    pid = pid:match("%d+")
    if not pid then return false, 0 end   -- proses mati -> bukan captcha
    -- hitung fd app_webview
    local out = sh("su -c 'ls /proc/" .. pid .. "/fd -la 2>/dev/null | grep -c app_webview'") or "0"
    local n = tonumber(out:match("%d+")) or 0
    return n >= CAPTCHA_WEBVIEW_AMBANG, n
end


-- Tungguin client bener-bener masuk game. Balik: true/false, lama, sebab.
--
-- v5.63 FIX: nilai awal WAJIB stabil dulu, gak boleh langsung dipakai.
-- Bug di v5.57: nilai awal diambil sekali, tepat habis client nyala -- dan saat
-- itu grafisnya masih 0.0 MB. Aturan "kini >= dasar * 2" jadi "kini >= 0",
-- yang SELALU benar. Hasilnya dia ngaku "masuk game setelah 5s" padahal client
-- masih di halaman awal, terus sapuan mulai kecepetan (persis yang mau
-- dihindarin).
--
-- Sekarang dua tahap:
--   Tahap 1  tungguin grafis NAIK lalu MENDATAR -> itu keadaan "udah di
--            halaman awal, selesai gambar". Nilai itu yang jadi patokan.
--   Tahap 2  baru tungguin dia naik tajam dari patokan itu -> masuk game.
function tunggu_masuk_game(pkg, batas, cek_batal)
    batas = batas or 150
    local mulai = os.time()
    local nama = pkg:gsub("com%.roblox%.", "")

    -- ---------- tahap 1: cari patokan yang stabil ----------
    local MIN_KB = 2000        -- di bawah 2 MB = belum gambar apa-apa
    -- ============================================================
    -- v5.78: AMBANG MUTLAK -- "udah gede" = udah di dalam game.
    --
    -- Cara lama cuma liat KENAIKAN: stabil dulu (itu jadi patokan "halaman
    -- awal"), baru tungguin naik tajam. Itu jebol kalau client masuk game
    -- LANGSUNG tanpa mampir halaman awal -- yang stabil justru nilai IN-GAME,
    -- terus worker nungguin kenaikan yang UDAH LEWAT.
    --
    -- Kejadian nyata: "grafis clienp mendatar di 42.2 MB -- itu patokan
    -- 'halaman awal'". Padahal ukur `velium layar` di RF yang sama:
    --     HOME 15 MB  ->  GAME 49 MB
    -- Jadi 42 MB itu jelas udah di dalam game. Worker nunggu sampai 84 MB (2x)
    -- atau 62 MB (+20MB) -- dua-duanya gak pernah datang.
    --
    -- 30 MB dipilih karena ada DI TENGAH dua nilai terukur itu, jauh dari
    -- dua-duanya. Bukan angka bulat asal.
    -- Ini cuma JALAN PINTAS: di bawah ambang, cara kenaikan yang lama tetep
    -- dipakai -- dia lebih peka buat RF yang nilainya beda.
    -- ============================================================
    local GAME_KB = 30000
    local dasar, sebelum = nil, 0
    while (os.time() - mulai) < batas do
        if cek_batal and cek_batal() then return false, os.time() - mulai, "STANDBY" end
        local kini = grafis_kb(pkg)
        if not kini then
            return false, os.time() - mulai, "meminfo gak kebaca"
        end
        -- jalan pintas: udah di atas ambang mutlak -> gak usah nunggu apa-apa
        if kini >= GAME_KB then
            info(("  grafis %s %.1f MB (>= %.0f MB) -- udah di dalam game"):format(
                nama, kini / 1024, GAME_KB / 1024))
            return true, os.time() - mulai
        end
        if kini >= MIN_KB then
            -- stabil = dua bacaan berurutan bedanya < 15%
            if sebelum > 0 and math.abs(kini - sebelum) < (sebelum * 0.15) then
                dasar = math.max(kini, sebelum)
                break
            end
            sebelum = kini
        end
        os.execute("sleep 3")
    end
    if not dasar then
        return false, os.time() - mulai,
            ("grafis gak pernah stabil di atas %.0f MB"):format(MIN_KB / 1024)
    end
    info(("  grafis %s mendatar di %.1f MB -- itu patokan 'halaman awal'")
        :format(nama, dasar / 1024))

    -- ---------- tahap 2: tungguin naik tajam ----------
    local puncak = dasar
    while (os.time() - mulai) < batas do
        if cek_batal and cek_batal() then return false, os.time() - mulai, "STANDBY" end
        os.execute("sleep 5")
        local kini = grafis_kb(pkg)
        if kini then
            if kini > puncak then puncak = kini end
            -- 2x patokan ATAU naik 20 MB -- mana pun kena duluan.
            -- Dua-duanya dipakai biar petak mungil (kena 2x) dan jendela besar
            -- (kena +20MB) sama-sama ketangkep.
            if kini >= dasar * 2 or (kini - dasar) >= 20000 then
                return true, os.time() - mulai
            end
        end
    end
    return false, os.time() - mulai,
        ("grafis cuma %.1f -> %.1f MB"):format(dasar / 1024, puncak / 1024)
end

function tunggu_jalan(pkg, batas, cek_batal, cfg, link)
    local mulai = os.time()
    local lastKabar = 0   -- v4.72: kabarin tiap 15 detik, biar gak keliatan diem
    -- v4.31: kalau prosesnya UDAH IDUP tapi belum sampai layar game, itu artinya
    -- LAGI LOADING -- bukan gagal. Dulu langsung di-'ulang', dan tiap ulang itu
    -- am start lagi -> loading keinterupsi terus -> gak pernah kelar (muter).
    -- Sekarang: dikasih perpanjangan waktu selama prosesnya masih idup.
    -- v4.59: dulu 3x -- kelamaan. Gabungan sama tunggu bridge bikin satu client
    -- bisa makan 6 menit. 2x udah cukup lega buat CPU 100%.
    local batasMax = batas * 2
    while (os.time() - mulai) < batasMax do
        local lewatBatas = (os.time() - mulai) >= batas
        if lewatBatas and not pkg_hidup(pkg) then
            break   -- lewat batas DAN prosesnya emang gak ada -> beneran gagal
        end
        if cek_batal and cek_batal() then return false, os.time()-mulai, "STANDBY" end
        -- v4.72: dulu bagian ini DIEM total sampai 2x batas -- keliatan kayak
        -- worker nyangkut padahal lagi nungguin Roblox nyala.
        local lewat = os.time() - mulai
        if lewat - lastKabar >= 15 then
            lastKabar = lewat
            io.write(("      %s â€” nungguin nyala... (%ds)\n"):format(
                pkg:gsub("com%%.roblox%%.",""), lewat))
        end
        if pkg_running(pkg) then
            -- muncul. verifikasi STABIL: cek 2x lagi (5s+5s). Roblox suka muncul
            -- sekejap terus mati pas RAM sesek -> jangan langsung dianggap sukses.
            os.execute("sleep 5")
            if not pkg_running(pkg) then
                return false, os.time() - mulai, "muncul lalu mati (RAM sesek?)"
            end
            os.execute("sleep 5")
            if not pkg_running(pkg) then
                return false, os.time() - mulai, "muncul lalu mati (RAM sesek?)"
            end
            -- v6.75: proses nyala != masuk game. Bisa NYANGKUT HOME (grafis
            -- rendah). Cek grafis: kalau masih rendah (< 30MB = Home/loading),
            -- TEMBAK link masuk + cek lagi. Ulang sampai grafis tinggi (di game)
            -- atau nyerah. Gitu "nungguin nyala" sekalian mastiin BENERAN MASUK,
            -- bukan cuma proses idup di Home.
            local cobaMasuk = 0
            while (os.time() - mulai) < batasMax do
                local g = grafis_kb(pkg) or 0
                if g >= 30000 then
                    return true, os.time() - mulai   -- grafis tinggi = di game
                end
                cobaMasuk = cobaMasuk + 1
                io.write(("      %s â€” di Home (%.0fMB), tembak masuk #%d...\n"):format(
                    pkg:gsub("com%%.roblox%%.",""), g/1024, cobaMasuk))
                -- v8.29: TEMBAK PAKAI WEB URL (cara WC), bukan cuma '-p pkg'.
                -- Dulu 'am start -a VIEW -p pkg' TANPA link = cuma bawa app ke
                -- depan, GAK nyuruh join game -> stuck Home (3MB). Sekarang tembak
                -- web URL + CLEAR_TOP (0x14000000) = beneran join game.
                if cfg and link and link ~= "" then
                    local pid_w = cfg.place_id or "129343810645058"
                    local kode_w = (link:match("accessCode=([%w%-]+)")
                        or link:match("linkCode=([%w%-]+)")
                        or link:match("privateServerLinkCode=([%w%-]+)")
                        or link:match("code=([%w%-]+)"))
                    local url_web
                    if link:find("share%?code=") or link:find("/share%?") then
                        url_web = link
                    elseif kode_w then
                        url_web = "https://www.roblox.com/games/start?placeId="..pid_w.."&accessCode="..kode_w
                    else
                        url_web = "https://www.roblox.com/games/start?placeId="..pid_w
                    end
                    sh_silent("su -c \"am start -a android.intent.action.VIEW -d '"..url_web.."' -p "..pkg.." -f 0x14000000\"")
                else
                    -- fallback lama (tanpa link) -- cuma bawa app ke depan
                    sh_silent("su -c 'am start -a android.intent.action.VIEW -p " .. pkg .. " 2>/dev/null'")
                end
                -- v8.74: tembak masuk tiap 40s (napas buat client masuk). Sleep
                -- dipecah 5s biar STANDBY + proses-mati tetep responsif.
                local sebabPecah = nil
                for _ = 1, 8 do
                    os.execute("sleep 5")
                    if cek_batal and cek_batal() then sebabPecah = "STANDBY" break end
                    if not pkg_running(pkg) then sebabPecah = "mati pas masuk game" break end
                end
                if sebabPecah then
                    return false, os.time()-mulai, sebabPecah
                end
                if not pkg_running(pkg) then
                    return false, os.time() - mulai, "mati pas masuk game"
                end
            end
            -- lewat batas tapi proses idup -> anggap sukses (di game / loading berat)
            return true, os.time() - mulai
        end
        os.execute("sleep 2")
    end
    local lama = os.time() - mulai
    if pkg_hidup(pkg) then
        -- proses idup tapi gak nyampe layar game: nyangkut loading / key-system /
        -- kelempar ke Home. am start ulang gak bakal nolong -- laporin apa adanya.
        return false, lama, "prosesnya idup tapi gak nyampe layar game (loading lama / nyangkut)"
    end
    return false, lama, "gak muncul sama sekali (RAM penuh? paket bener?)"
end

-- v4.4: tutup PAKSA semua client Roblox (am force-stop). buat CLOSE & REJOIN dari panel.
-- v4.9: baca username Roblox tiap client dari prefs.xml. buat mapping client<->akun,
-- biar worker tau "clienu = fifinx_5". dipakai auto-rejoin: kalau akun X berhenti
-- lapor (keluar game), worker tau itu client mana -> rejoin client itu.
function baca_username(pkg)
    local path = "/data/data/" .. pkg .. "/shared_prefs/prefs.xml"
    local o = sh("su -c 'cat " .. path .. "'")
    -- <string name="username">fifinx_5</string>
    local u = o:match('<string name="username">(.-)</string>')
    return u
end

-- v4.8: tulis LOADER ke autoexec Delta (/sdcard/Delta/Autoexecute/).
-- Delta auto-jalanin file di folder ini pas masuk game (SETELAH user verif key).
-- jadi: worker buka client -> user verif key manual -> Delta baca autoexec ->
-- script auto-jalan. user cuma verif key, script masuk sendiri.
-- 1 RF = 1 game, jadi 1 loader (sesuai game tim) buat semua client.
-- v5.29: url bisa DITIMPA panel (script per tim). Kalau urlPanel dikasih,
-- itu yang dipakai; kalau nggak, jatuh ke cfg.script_url lokal RF kayak dulu.
function tulis_autoexec(cfg, urlPanel)
    -- v9.263: Arceus -> loader udah ditulis pasang.sh (velium.lua statis). Worker GAK usah
    -- nulis velium_loader.txt di sini (biar gak dobel loader + ilangin warning "GAGAL nulis").
    if cfg.executor == "arceus" then
        return true
    end
    local url_script = (urlPanel and urlPanel ~= "") and urlPanel or cfg.script_url
    if not url_script or url_script == "" then
        warn("script_url kosong, autoexec dilewat")
        return false
    end
    local AUTOEXEC_DIR = cfg.autoexec_dir or "/sdcard/Delta/Autoexecute"
    -- loader: narik script dari GitHub. update cukup di GitHub, file autoexec tetap.
    -- v9.261: HAPUS cache market DULU sebelum fetch. Bug: market.lua nyimpen
    -- ZenxMarket_cache.lua (buat re-exec teleport) -- kalau cache lama, client
    -- NYANGKUT di versi lama walau GitHub udah update / dihapus. delfile cache dulu
    -- -> fresh join PASTI fetch versi baru. pcall + guard biar aman non-market.
    local loader = 'pcall(function() if delfile then pcall(delfile,"ZenxMarket_cache.lua") pcall(delfile,"ZenxMarket_cache_time.txt") end end) loadstring(game:HttpGet("' .. url_script .. '"))()'
    -- ============================================================
    -- v5.61: LOADER = .txt DOANG.
    --
    -- Dasarnya pengalaman berulang user: pakai .txt SELALU jalan. Itu bukti
    -- yang lebih kuat daripada tebakan gua, jadi salinan .lua dibuang.
    --
    -- Kenapa gak ditulis dua-duanya buat aman: kalau ternyata Delta baca SEMUA
    -- berkas di folder itu, script kejalanin 2x -- dua kali unduh dari GitHub
    -- dan dua salinan jalan barengan sebentar. Di RF 4GB dengan 4 client itu
    -- pemborosan yang gak perlu, dan .txt udah kebukti cukup.
    --
    -- Catatan sejarah biar gak keulang: sepanjang sesi debug ini gejalanya
    -- "autoexec kebaca ketulis & terverifikasi TAPI script gak pernah jalan".
    -- Itu ada DUA sebab yang numpuk:
    --   1. nama berkasnya .lua (bagian ini)
    --   2. Delta nyangkut di layar "Enter key" -- autoexec gak jalan sampai
    --      Delta kebuka (diberesin v5.46-5.58)
    -- Yang bikin susah dilacak: semua pemeriksaan di sisi worker LOLOS.
    -- ============================================================
    local path = AUTOEXEC_DIR .. "/velium_loader.txt"
    -- Tulis lewat file lokal dulu (Termux home, gampang), baru cp ke folder Delta
    -- pakai su. Ini ngehindarin neraka nested-quote (su -c ' ... " ... ').
    local tmp = os.getenv("HOME") .. "/.velium_loader.tmp"
    local f = io.open(tmp, "w")
    if not f then warn("gagal bikin file tmp loader"); return false end
    f:write(loader); f:close()
    -- ============================================================
    -- v5.41: BERSIHIN FILE LAIN di folder autoexec.
    --
    -- Delta jalanin SEMUA file di folder ini. Jadi sisa script lama (mis.
    -- text.txt yang pernah ditaruh manual, atau loader dari nama lama) bakal
    -- jalan BARENGAN sama yang baru -> dua script aktif di satu client, aksi
    -- dobel, atau yang bener ketimpa yang salah.
    --
    -- Digabung ke panggilan su yang SAMA -- tiap 'su' di RedFinger ~6 detik,
    -- jadi pembersihan ini praktis gratis.
    -- Yang dilewat cuma loader punya kita sendiri.
    -- Mau dimatiin? config -> autoexec_bersih=false
    -- ============================================================
    local bersih = ""
    if cfg.autoexec_bersih ~= false then
        bersih = "for f in " .. AUTOEXEC_DIR .. "/*; do " ..
                 '[ -f "$f" ] || continue; ' ..
                 'case "$f" in */velium_loader.txt) ;; ' ..
                 '*) echo "HAPUS:$f"; rm -f "$f";; esac; ' ..
                 "done; "
    end

    -- v4.62: mkdir + cp + chmod + verifikasi digabung jadi SATU panggilan su.
    -- Dulu 4 panggilan terpisah -- tiap 'su -c' di RedFinger ~5-7 detik, jadi
    -- bagian ini sendirian makan ~30 detik pas worker nyala.
    local cek = sh("su -c 'mkdir -p " .. AUTOEXEC_DIR .. "; " .. bersih ..
                   "cp " .. tmp .. " " .. path ..
                   "; chmod 664 " .. path ..
                   "; cat " .. path .. "'")

    -- lapor apa aja yang dibuang, biar gak ada yang ilang diam-diam
    local dibuang = {}
    for nm in tostring(cek):gmatch("HAPUS:([^\n]+)") do
        dibuang[#dibuang+1] = nm:match("([^/]+)$") or nm
    end
    if #dibuang > 0 then
        warn("file lain di folder autoexec dibuang: " .. table.concat(dibuang, ", "))
        warn("  (Delta jalanin SEMUA file di situ -- kalau dibiarin, script dobel)")
    end

    if cek:find("loadstring", 1, true) then
        -- v5.65: sebut LOKASI berkasnya, bukan cuma "ditulis". Dulu pesannya
        -- cuma nyebut URL script -- jadi kalau ada yang bingung "kok berkasnya
        -- gak ada", gak ada cara ngecek selain buka file manager.
        ok("autoexec ditulis: " .. path)
        info("  isi: loadstring(...\"" .. url_script .. "\")...")
        -- tunjukin isi folder biar gak ada keraguan
        local isiFolder = sh("su -c 'ls -l " .. AUTOEXEC_DIR .. " 2>&1 | tail -n +2'") or ""
        if isiFolder ~= "" then
            for baris in isiFolder:gmatch("[^\r\n]+") do
                local nm = baris:match("(%S+)%s*$")
                local sz = baris:match("%s(%d+)%s+%d%d%d%d%-") or baris:match("root%s+(%d+)%s")
                if nm and nm ~= "" then
                    info("  folder: " .. nm .. (sz and ("  " .. sz .. " B") or ""))
                end
            end
        end
        return true
    else
        warn("GAGAL nulis autoexec ke " .. path)
        warn("  yang kebaca balik: " .. tostring(cek):sub(1, 120))
        warn("  cek izin folder Delta / root masih jalan?")
        return false
    end
end

-- v4.12: bawa SEMUA client freeform ke depan sekaligus. pas pencet Termux/app lain,
-- jendela Roblox ke-belakang. FRONT = am start tiap client yg udah jalan -> window
-- muncul ke depan LAGI (Roblox udah jalan, am start cuma munculin window, gak restart).
-- karena Delta freeform, semua jendela bisa nampil barengan di samping-samping.
function front_all(cfg, mapLink)
    local list = split(cfg.pkgs)
    local n = 0
    for _, pkg in ipairs(list) do
        if pkg_running(pkg) then
            -- am start dgn flag REORDER_TO_FRONT (0x20000000): bawa window yg UDAH ADA
            -- ke depan, JANGAN restart game. tanpa flag ini am start bisa reload.
            local url = build_url(cfg, mapLink and mapLink[pkg] or nil)
            sh_silent("su -c \"am start -f 0x20000000 -a android.intent.action.VIEW -d '" .. url .. "' -p " .. pkg .. "\"")
            n = n + 1
            os.execute("sleep 1")   -- jeda tipis biar window ketata rapi
        end
    end
    return n
end


-- v4.71: ambil taskId SEMUA client dari SATU dump. Dulu tiap client nyoba 4
-- sumber berbeda -- 4 client = 16 panggilan 'su' = ~96 detik cuma buat nyusun
-- grid. Sekarang: satu dump, dipilah lokal; sumber cadangan cuma dipakai kalau
-- masih ada yang belum ketemu.
POLA_TASK = {
    "taskId=(%d+)", "Task{%w+%s+#(%d+)", "#(%d+)%s+type=",
    "taskId%s*=%s*(%d+)", "Task%s+id=(%d+)", "id=(%d+)",
}
function task_id_semua(pkgs)
    local hasil = {}
    local function pungut(o)
        for baris in (o or ""):gmatch("[^\r\n]+") do
            for _, p in ipairs(pkgs) do
                if not hasil[p] and baris:find(p, 1, true) then
                    for _, pat in ipairs(POLA_TASK) do
                        local id = baris:match(pat)
                        if id and tonumber(id) and tonumber(id) > 0 then
                            hasil[p] = tonumber(id); break
                        end
                    end
                end
            end
        end
    end
    -- satu dump dulu; kalau semua udah ketemu, gak usah lanjut
    pungut(sh("su -c 'dumpsys activity activities'"))
    local kurang = false
    for _, p in ipairs(pkgs) do if not hasil[p] then kurang = true break end end
    if kurang then pungut(sh("su -c 'dumpsys activity recents'")) end
    kurang = false
    for _, p in ipairs(pkgs) do if not hasil[p] then kurang = true break end end
    if kurang then pungut(sh("su -c 'am stack list 2>/dev/null'")) end
    return hasil
end

-- ============================================================
-- v4.82: TATA JENDELA LEWAT PREFS APP CLONER
--
-- Kenapa bukan 'am ... resize': jendela ngambang itu DIGAMBAR APP CLONER,
-- bukan Android. Android nganggep semua klon fullscreen (mWindowingMode=
-- fullscreen, bounds=[0,0][layar penuh]) -- App Cloner nggambar kotaknya DI
-- DALAM jendela fullscreen itu. Jadi perintah apa pun ke Android sia-sia:
--   am task resizeTask    -> gak ada di ROM RedFinger
--   am stack resize       -> keterima TAPI gak ngefek
--   am task resize        -> Exception / gak ngefek
--   --windowingMode 5     -> jalan, tapi Android nambah batang judul -> KOTAK DOBEL
-- Yang jalan: tulis koordinat ke shared_prefs klon, terus buka aplikasinya.
--
-- ATURAN YANG GAK BISA DITAWAR:
--   * WAJIB nulis DUA set: current_ DAN original_. Cuma current_ -> balik
--     berantakan (App Cloner pakai original_ pas jendela pertama dibuka).
--   * DITULIS PAS CLIENT MATI, sebelum dibuka. App Cloner baca prefs pas app
--     MULAI, dan NIMPA BALIK pas app DITUTUP.
--   * Petak dihitung dari urutan cfg.pkgs (TETAP), bukan urutan buka -- worker
--     suka ngurutin ulang, kalau ikut itu jendelanya pindah-pindah tiap ronde.
-- ============================================================
SELA = 15   -- jarak antar jendela = SELA x 2

-- templat dipilih tangan; rumus akar kuadrat boros (8 client jadi 3x3, nganggur 1)
SUSUNAN = {
    [1]={1,1}, [2]={2,1}, [3]={3,1},  [4]={2,2},
    [5]={3,2}, [6]={3,2}, [7]={4,2},  [8]={4,2},
    [9]={3,3}, [10]={5,2},[11]={4,3}, [12]={4,3},
    -- v9.205: tim 1 = 15 client -> 5 kolom x 3 baris. Buka CHUNK 5 (5+5+5, 90s antar
    -- chunk) -> tiap chunk = 1 baris 5 kolom. Device cuma nanggung 5 pas buka.
    -- v9.208: 16-20 buat TES `velium buka N` (semua 5 kolom, N/5 baris).
    [13]={5,3},[14]={5,3},[15]={5,3},
    [16]={5,4},[17]={5,4},[18]={5,4},[19]={5,4},[20]={5,4},
}

KUNCI_JENDELA = {
    "app_cloner_current_window_left",   "app_cloner_current_window_top",
    "app_cloner_current_window_right",  "app_cloner_current_window_bottom",
    "app_cloner_original_window_left",  "app_cloner_original_window_top",
    "app_cloner_original_window_right", "app_cloner_original_window_bottom",
}

-- v9.17: HAPUS SEMUA posisi window dari prefs SEMUA client (bener2 bersih).
-- User: sebelum Start, pastiin posisi kolom LAMA hilang SEMUA dulu, baru timpa
-- yg baru -> gak campur (ada 5 kolom ada 3 kolom nyangkut). Dipanggil di awal
-- RESTART sebelum tulis grid. Buang key app_cloner_*window* dari tiap prefs.
function bersihin_grid_semua(cfg)
    -- v9.131: BATCH -- tulis 1 shell script (sed -i semua prefs file), jalanin
    -- sekali via su. Dulu per-client (su cat + gsub + su write) x40 operasi ~13s.
    -- Sekarang 1 su call, semua client sekaligus. Pakai '.' di regex buat match
    -- tanda kutip (biar gak ribet escape " di dalem sed).
    local pkgs = split(cfg.pkgs or "")
    if #pkgs == 0 then return 0 end
    local files = {}
    for _, pkg in ipairs(pkgs) do
        files[#files+1] = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
        files[#files+1] = "/data/data/" .. pkg .. "/shared_prefs/prefs.xml"
    end
    local HOME = os.getenv("HOME") or "/data/data/com.termux/files/home"
    local script = HOME .. "/.gridbersih.sh"
    local f = io.open(script, "w")
    if not f then
        warn("[grid] gagal tulis script bersih -- skip")
        return 0
    end
    f:write("#!/system/bin/sh\n")
    local sedExpr = "s|<int name=.app_cloner_[a-zA-Z0-9_]*window[a-zA-Z0-9_]*.[^/]*/>||g; "
                 .. "s|<int name=.app_cloner_[a-zA-Z0-9_]*position[a-zA-Z0-9_]*.[^/]*/>||g; "
                 .. "s|<int name=.app_cloner_[a-zA-Z0-9_]*geometry[a-zA-Z0-9_]*.[^/]*/>||g"
    for _, path in ipairs(files) do
        f:write('[ -f "' .. path .. '" ] && sed -i -E \'' .. sedExpr .. '\' "' .. path .. '" 2>/dev/null\n')
    end
    f:close()
    sh_silent("su -c 'sh " .. script .. "'")
    local n = #pkgs
    info(("Grid lama dihapus dari %d client SEKALIGUS (sed batch, bersih total)"):format(n))
    return n
end

-- (fungsi lama per-client di bawah diganti batch di atas -- disimpen buat referensi)
function bersihin_grid_semua_LAMA(cfg)
    local n = 0
    for _, pkg in ipairs(split(cfg.pkgs)) do
        local nm = pkg:gsub("com%.roblox%.", "")
        -- v9.19: bersihin KEDUA prefs file per client (App Cloner + Roblox/Delta).
        -- User: hapus SEMUA bekas grid dari mana pun. Grid position utama di
        -- App Cloner (_preferences.xml), tapi jaga-jaga bersihin prefs.xml juga.
        local paths = {
            "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml",
            "/data/data/" .. pkg .. "/shared_prefs/prefs.xml",
        }
        local adaHapus = false
        for _, path in ipairs(paths) do
            local isi = sh("su -c 'cat " .. path .. " 2>/dev/null'") or ""
            if isi:find("<map", 1, true) then
                local bersih = isi
                local kena = 0
                for _ in isi:gmatch('name="app_cloner_[%w_]*window[%w_]*"') do kena = kena + 1 end
                -- buang SEMUA <int> app_cloner window/position/geometry
                bersih = bersih:gsub('%s*<int name="app_cloner_[%w_]*window[%w_]*"[^/]*/>', "")
                bersih = bersih:gsub('%s*<int name="app_cloner_[%w_]*position[%w_]*"[^/]*/>', "")
                bersih = bersih:gsub('%s*<int name="app_cloner_[%w_]*geometry[%w_]*"[^/]*/>', "")
                if bersih ~= isi then
                    local tmp = (os.getenv("HOME") or "/data/data/com.termux/files/home") .. "/.gridbersih.tmp"
                    local f = io.open(tmp, "w")
                    if f then
                        f:write(bersih); f:close()
                        sh_silent("su -c 'cat " .. tmp .. " > " .. path .. "'")
                        adaHapus = true
                        if kena > 0 then
                            info(("  grid lama %s dihapus (%d key window, %s)"):format(
                                nm, kena, path:find("_preferences") and "AppCloner" or "prefs"))
                        end
                    end
                end
            end
        end
        if adaHapus then n = n + 1
        else info(("  grid %s: gak ada key window (bersih / format beda?)"):format(nm)) end
    end
    if n > 0 then info(("Grid lama dihapus dari %d client (kedua prefs, bersih total)"):format(n)) end
    return n
end


-- balikin: peta pkg -> {L,T,R,B}, sebab, kol, bar, W, H
-- v5.06: hitung petak buat JUMLAH CLIENT SEMBARANG (bukan cuma yang kepasang).
-- Gunanya: satu client dipakai buat nyoba semua ukuran. Mau tau petaknya kalau
-- nanti 10 client? Set jendela client ini ke ukuran itu, cari tombolnya,
-- simpen. Gak usah beneran buka 10 client.
function petak_untuk(n, slot, cfg)
    local W, H = layar_ukuran()
    if W == 0 or H == 0 then return nil, "gagal baca ukuran layar" end
    if not n or n < 1 then return nil, "jumlah client gak masuk akal" end
    slot = slot or 1
    -- v7.06: paksa landscape (W = sisi panjang) -- samain dgn grid_hitung.
    if W < H then W, H = H, W end

    local kol, bar
    -- v9.241: respect BARIS override dari panel (grid_kolom = baris) biar konsisten sama
    -- grid utama (grid_hitung). Gak dikasih cfg / 0 -> auto SUSUNAN/sqrt.
    local barPaksa = cfg and tonumber(cfg.grid_kolom)
    if barPaksa and barPaksa >= 1 then
        bar = math.min(barPaksa, n)
        kol = math.ceil(n / bar)
    else
        local s = SUSUNAN[n]
        if s then
            kol, bar = s[1], s[2]
        elseif W >= H then
            kol = math.ceil(math.sqrt(n)); bar = math.ceil(n / kol)
        else
            bar = math.ceil(math.sqrt(n)); kol = math.ceil(n / bar)
        end
    end

    local lebar, tinggi = math.floor(W / kol), math.floor(H / bar)
    local c = (slot - 1) % kol
    local r = math.floor((slot - 1) / kol)
    return {
        L = c * lebar + SELA,
        T = r * tinggi + SELA,
        R = (c + 1) * lebar - SELA,
        B = (r + 1) * tinggi - SELA,
    }, kol, bar, W, H
end

-- v5.20 (BUKTI LAPANGAN): grid 3 BARIS gak bisa dipakai bypass key.
-- Di layar 1280x720, 3 baris bikin tinggi jendela cuma ~173px -- dialog key
-- Delta gak muat, tombolnya kepotong. Udah dicoba di 9 client: gagal.
-- Jadi batas aman = 8 client (masih 2 baris, tinggi ~293px). Ini batas LAYAR,
-- beda dari batas RAM -- dua-duanya harus dilewatin.
function baris_grid(n, W, H)
    local s = SUSUNAN[n]
    if s then return s[2] end
    if W >= H then return math.ceil(n / math.ceil(math.sqrt(n))) end
    return math.ceil(math.sqrt(n))
end

function grid_hitung(cfg, pkgsPilih)
    local W, H = layar_ukuran()   -- udah nuker W/H kalau layar landscape
    if W == 0 or H == 0 then return nil, "gagal baca ukuran layar (wm size)" end

    -- v7.06: PAKSA LANDSCAPE. RF kadang tiba-tiba balik portrait (wm size baca
    -- 720x1280), tapi grid HARUS tetep dihitung kayak landscape (W = sisi
    -- PANJANG, H = sisi pendek). Kalau W < H (kebaca portrait), TUKER -> W jadi
    -- sisi panjang. Jadi grid 10 client selalu 5x2 (landscape), gak berantakan
    -- jadi 2x5 sempit pas layar kebaca portrait. Client tetep landscape.
    if W < H then
        W, H = H, W
    end

    -- v8.19: kalau dikasih pkgsPilih (client yg MAU DIBUKA), grid dihitung buat
    -- JUMLAH ITU -- bukan semua cfg.pkgs. Jadi start 2 client = grid 2 petak
    -- lebar, bukan 10 petak kecil. Kalau nil -> semua (perilaku lama).
    -- v9.266: GRID PAKSA PENUH buat MARKET (2-tim 3+3) / Arceus. Bug user: kalau cuma
    -- 1 tim (3 client) yg aktif, grid dihitung basis 3 -> jadi 2x2 (slot gede, layout
    -- beda tiap tim). User mau layout 3x2 TETAP (basis 6), client aktif tinggal nempatin
    -- slot-nya (0,1,2 = baris atas; 3,4,5 = baris bawah). Jadi dimensi + peta basis SEMUA
    -- client, walau yg dibuka cuma subset. peta punya posisi semua 6 -> caller ambil yg perlu.
    local pkgsFull = split(cfg.pkgs)
    local paksaPenuh = (cfg.script_label == "MARKET") or (cfg.executor == "arceus")
    local pkgs
    if paksaPenuh then
        pkgs = pkgsFull                    -- basis PENUH (6) -> 3x2 konsisten
    else
        pkgs = pkgsPilih or pkgsFull       -- perilaku lama: subset -> grid subset
    end
    local n = #pkgs
    if n == 0 then return nil, "gak ada client di config" end
    -- v9.14: DETEKSI duplikat pkg (sebab grid nimpa). Kalau ada pkg dobel di
    -- daftar -> log warning (biar user tau config-nya ada dobel).
    do
        local ce = {}
        for _, p in ipairs(pkgs) do
            ce[p] = (ce[p] or 0) + 1
            if ce[p] == 2 then
                warn("[grid] DUPLIKAT pkg: " .. p:gsub("com%.roblox%.", "") .. " (config ada dobel -> bisa bikin nimpa, di-dedup)")
            end
        end
    end

    local kol, bar
    -- v9.240: OVERRIDE dari panel = JUMLAH BARIS (bukan kolom lagi). User: set BARIS
    -- lebih jelas + BENER buat bypass -- posisi tombol key ditentuin jumlah BARIS (1
    -- baris Y0.713, 2 baris Y0.723, 3 baris Y0.808). Baris di-set -> kolom dihitung dari
    -- jumlah client. (field-nya masih 'grid_kolom' biar gak mecah config lama, tapi ARTINYA baris.)
    local barPaksa = tonumber(cfg.grid_kolom)
    if barPaksa and barPaksa >= 1 then
        bar = math.min(barPaksa, n)
        kol = math.ceil(n / bar)
    else
        local s = SUSUNAN[n]
        if s then
            kol, bar = s[1], s[2]
        elseif W >= H then
            kol = math.ceil(math.sqrt(n)); bar = math.ceil(n / kol)
        else
            bar = math.ceil(math.sqrt(n)); kol = math.ceil(n / bar)
        end
    end
    -- v6.71: JARING PENGAMAN landscape. TAPI v9.240: JANGAN swap kalau user set BARIS
    -- eksplisit (hormati pilihan user -- baris = yg nentuin tombol key). Auto aja yg di-swap.
    if not (barPaksa and barPaksa >= 1) and W >= H and n >= 2 and kol < bar then
        kol, bar = bar, kol
    end
    -- pastiin kol*bar cukup nampung semua client (jangan ada yang kepotong)
    while kol * bar < n do kol = kol + 1 end

    local lebar, tinggi = math.floor(W / kol), math.floor(H / bar)
    local peta = {}
    -- v9.14: DEDUP -- kalau pkgs ada duplikat, skip yg udah ke-assign (biar 2
    -- client gak dapet index sama = posisi NIMPA). Pakai idx terpisah yg cuma
    -- naik buat pkg UNIK. Bug user: 2 client posisi persis sama (numpuk penuh).
    local idxUnik = 0
    local udahAssign = {}
    for _, pkg in ipairs(pkgs) do   -- URUTAN CONFIG, jangan urutan buka
        if not udahAssign[pkg] then
            udahAssign[pkg] = true
            local c = idxUnik % kol
            local r = math.floor(idxUnik / kol)
            peta[pkg] = {
                L = c * lebar + SELA,
                T = r * tinggi + SELA,
                R = (c + 1) * lebar - SELA,
                B = (r + 1) * tinggi - SELA,
            }
            idxUnik = idxUnik + 1
        end
    end
    return peta, nil, kol, bar, W, H, lebar, tinggi
end

function prefs_path(pkg)
    return "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
end

-- tulis koordinat 1 client. balikin: berhasil, keterangan
-- keterangan "udah pas" = gak ada yang ditulis (hemat 1 panggilan su)
function tata_satu(pkg, kotak, hapusDulu)
    local path = prefs_path(pkg)
    -- stderr digabung DI DALAM su -- kalau dibuang, penolakan ROM ikut kebuang
    -- dan kodenya ngira sukses padahal gagal.
    local isi = sh("su -c 'cat " .. path .. " 2>&1'") or ""
    if not isi:find("<map", 1, true) then
        return false, "prefs belum ada (client belum pernah dibuka)"
    end

    -- v8.67: HAPUS SEMUA key posisi window LAMA dulu (user minta bener2 bersih).
    -- Buang semua <int name="app_cloner_*window*"> yg ada -> gak ada sisa posisi
    -- lama nyangkut (beda format/nilai basi). Baru tulis yg baru di bawah.
    if hapusDulu then
        isi = isi:gsub('%s*<int name="app_cloner_[%w_]*window[%w_]*"[^/]*/>', "")
    end

    local mau = {}
    for _, k in ipairs(KUNCI_JENDELA) do
        local v
        if     k:find("_left$")   then v = kotak.L
        elseif k:find("_top$")    then v = kotak.T
        elseif k:find("_right$")  then v = kotak.R
        else                           v = kotak.B end
        mau[k] = v
    end

    -- udah pas? lewatin nulisnya -- hemat 1 su per client tiap ronde
    -- (SKIP cek ini kalau hapusDulu -- posisi lama udah dibuang, WAJIB tulis ulang)
    if not hapusDulu then
        local udahPas = true
        for k, v in pairs(mau) do
            local ada = tonumber(isi:match('<int name="' .. k .. '" value="(%-?%d+)"'))
            if ada ~= v then udahPas = false break end
        end
        if udahPas then return true, "udah pas" end
    end

    local baru = isi
    for k, v in pairs(mau) do
        local ganti = string.format('<int name="%s" value="%d" />', k, v)
        if baru:find('<int name="' .. k .. '"', 1, true) then
            baru = baru:gsub('<int name="' .. k .. '"[^/]*/>', function() return ganti end, 1)
        else
            baru = baru:gsub("</map>", function() return "    " .. ganti .. "\n</map>" end, 1)
        end
    end

    -- JANGAN pakai sed di dalam su -- '</map>' kebaca shell sebagai pengalihan
    -- ("syntax error: unexpected '<'"). Jadi: ubah di Lua, tulis lewat berkas
    -- sementara, salin pakai 'cat tmp > target' (bukan cp) biar pemilik & izin
    -- berkas aslinya tetep.
    local tmp = (os.getenv("HOME") or ".") .. "/.velium_prefs.tmp"
    local f = io.open(tmp, "w")
    if not f then return false, "gagal bikin berkas sementara" end
    f:write(baru); f:close()

    local out = sh("su -c 'cat " .. tmp .. " > " .. path .. " 2>&1'") or ""
    os.remove(tmp)
    if out:match("%S") then return false, "gagal nulis: " .. out:gsub("%s+", " "):sub(1, 60) end
    return true, "ditulis"
end

-- v7.61: tata grid 1 CLIENT aja (buat dipanggil sebelum masukin per client).
-- Hitung grid semua (grid_hitung) -> ambil kotak client ini -> tulis prefs.
-- Ringan (cuma tulis prefs 1 client, gak force-stop). Dipanggil sebelum open_one
-- di jalur masukin (grafis-out / script-off) biar client masuk langsung di posisi.
GRID_CACHE = nil   -- cache peta grid (biar gak hitung ulang tiap client)
PKGS_AKTIF = nil   -- v8.88: client yg aktif dibuka (FORCE:daftar) -> grid pakai ini
PKGS_AKTIF_PULIH = false   -- v9.84: udah coba pulihin PKGS_AKTIF dari start-pilih (sekali per boot)
AKTIF_SIG = ""     -- v9.89: signature state aktif terakhir yg disimpen (biar gak nulis-nulis)

-- v9.89: SIMPAN STATE AKTIF (server + grid + daftar client) ke file lokal.
-- Biar abis UPDATE/REBOOT, worker buka PERSIS yg tadi jalan -- gak balik ke 10
-- client / grid campur. place_id & grid_kolom sebenernya udah di config, tapi
-- daftar client (PKGS_AKTIF) ilang tiap restart. File ini nyimpen ketiganya.
-- Format 1 baris:  <place_id>|<grid_kolom>|<pkg1,pkg2,...>
function simpan_aktif(cfg)
    local daftar = ""
    -- v9.94: JANGAN simpen daftar kalau = SEMUA client (racun). Itu bukan pilihan
    -- asli (biasanya fallback polos yg ke-save). Simpen HANYA kalau subset (< total).
    -- Kalau semua -> daftar kosong -> pulih gak restore semua (biar gak buka 10).
    if PKGS_AKTIF and #PKGS_AKTIF > 0 and #PKGS_AKTIF < #split(cfg.pkgs) then
        daftar = table.concat(PKGS_AKTIF, ",")
    end
    local sig = string.format("%s|%s|%s", tostring(cfg.place_id or ""),
        tostring(cfg.grid_kolom or 0), daftar)
    if sig == AKTIF_SIG then return end   -- gak berubah -> gak usah nulis
    AKTIF_SIG = sig
    local jalur = (os.getenv("HOME") or ".") .. "/.velium_aktif"
    local f = io.open(jalur, "w")
    if f then f:write(sig); f:close() end
end

-- v9.93: string perintah FORCE dari PKGS_AKTIF (client aktif). "FORCE:akun1,..."
-- kalau ada daftar, "FORCE" polos kalau nil. Dipakai UPDATE/REBOOT reset perintah
-- DB -> abis reboot worker baca FORCE:daftar -> buka PERSIS client yg tadi aktif
-- (6), GAK tergantung file state / pulih / mapAkun (yg bisa 10 akun).
function force_str(cfg, mapAkun)
    if PKGS_AKTIF and #PKGS_AKTIF > 0 then
        local nm = {}
        for _, pkg in ipairs(PKGS_AKTIF) do
            local u = mapAkun and mapAkun[pkg]
            nm[#nm+1] = (u and tostring(u) ~= "") and tostring(u) or pkg:gsub("com%.roblox%.", "")
        end
        if #nm > 0 then return "FORCE:" .. table.concat(nm, ",") end
    end
    return "FORCE"
end

-- v9.89: PULIHIN state aktif dari file pas boot. Set cfg.place_id + grid_kolom +
-- PKGS_AKTIF. Dipanggil SEBELUM loop utama -> open pertama pakai state bener.
function pulih_aktif(cfg)
    local jalur = (os.getenv("HOME") or ".") .. "/.velium_aktif"
    local f = io.open(jalur, "r")
    if not f then return false end
    local baris = (f:read("*l") or ""); f:close()
    local place, grid, daftar = baris:match("^(.-)|(.-)|(.*)$")
    if not place then return false end
    -- server (place_id) + grid_kolom -> ke config kalau ada isinya
    if place ~= "" and place ~= tostring(cfg.place_id or "") then
        cfg.place_id = place
        pcall(function() save_config(cfg) end)
    end
    local gk = tonumber(grid)
    if gk and gk ~= (tonumber(cfg.grid_kolom) or 0) then
        cfg.grid_kolom = gk
        pcall(function() save_config(cfg) end)
    end
    -- daftar client -> PKGS_AKTIF (cocokin sama cfg.pkgs biar valid)
    if daftar and daftar ~= "" then
        local total = #split(cfg.pkgs)
        local adaCfg = {}
        for _, p in ipairs(split(cfg.pkgs)) do adaCfg[p] = true end
        local pk = {}
        for p in daftar:gmatch("[^,]+") do if adaCfg[p] then pk[#pk+1] = p end end
        -- v9.94: RACUN = daftar >= SEMUA client. Itu bukan pilihan asli (fallback
        -- polos ke-save). Buang file OTOMATIS + jangan restore -> worker gak buka 10.
        if #pk >= total then
            os.remove(jalur)
            AKTIF_SIG = ""
            info(("[boot] file state RACUN (daftar %d = semua) -> DIBUANG, gak restore daftar"):format(#pk))
            return false
        end
        if #pk > 0 and #pk < total then
            PKGS_AKTIF = pk
            AKTIF_SIG = baris
            return true, #pk, place, gk
        end
    end
    return false
end

-- v8.90: grid_satu BUANG CACHE. Cache (GRID_CACHE) sumber utama "grid nyangkut
-- lama" -- nilai basi kesimpen, gak ke-reset di semua jalur. Sekarang: hitung
-- grid FRESH tiap panggil, dari PKGS_AKTIF (client yg panel pilih). grid_hitung
-- murah (baca ukuran layar 1x), gak perlu cache. Fresh = gak akan nyangkut.
function grid_satu(cfg, pkg)
    if cfg.auto_grid ~= true then return end   -- grid mati -> lewat
    -- hitung grid FRESH buat client aktif (PKGS_AKTIF). nil = semua client.
    local peta = grid_hitung(cfg, PKGS_AKTIF)
    if peta and peta[pkg] then
        tata_satu(pkg, peta[pkg], true)   -- hapus posisi lama + tulis fresh
        -- v9.251: DIAGNOSTIK -- keliatan grid pakai basis berapa client. Kalau 6-10
        -- keluar "basis 5" = PKGS_AKTIF ke-reset jadi 5 (bug). Harusnya "basis 10".
        info(("[grid] %s -> grid basis %d client"):format(tostring(pkg):sub(-10), #(PKGS_AKTIF or {})))
    end
end

function atur_grid_lama(cfg)
    local W, H, rot = layar_ukuran()
    if W == 0 or H == 0 then
        return 0, "gagal baca ukuran layar (wm size)"
    end

    -- kumpulin client yang lagi jalan
    local aktif = {}
    for _, pkg in ipairs(split(cfg.pkgs)) do
        if pkg_running(pkg) then aktif[#aktif+1] = pkg end
    end
    local n = #aktif
    if n == 0 then return 0, "gak ada client jalan" end

    -- v4.27: bentuk grid NGIKUT bentuk layar.
    --   landscape (lebar > tinggi) -> kolom lebih banyak (6 client = 3x2)
    --   portrait  (tinggi > lebar) -> baris lebih banyak (6 client = 2x3)
    -- kalau dipaksa sama, jendelanya jadi kurus/gepeng gak kepake.
    local kol, bar
    if W >= H then
        kol = math.ceil(math.sqrt(n)); bar = math.ceil(n / kol)
    else
        bar = math.ceil(math.sqrt(n)); kol = math.ceil(n / bar)
    end
    local lebar  = math.floor(W / kol)
    local tinggi = math.floor(H / bar)

    -- v4.71: taskId semua client sekali ambil, terus SEMUA resize dikirim dalam
    -- SATU panggilan su. Dulu: 4 sumber x tiap client buat cari id, plus 1 su
    -- per resize -- totalnya bisa 20 panggilan (~2 menit).
    local petaId = task_id_semua(aktif)
    local sukses, gagalPertama = 0, nil
    local perintah = {}
    for i, pkg in ipairs(aktif) do
        local id = petaId[pkg]
        if not id then
            gagalPertama = gagalPertama or ("taskId " .. pkg:gsub("com%.roblox%.","") .. " gak ketemu")
        else
            local c = (i - 1) % kol              -- kolom ke-berapa
            local r = math.floor((i - 1) / kol)  -- baris ke-berapa
            local L, T = c * lebar, r * tinggi
            perintah[#perintah+1] = string.format("am task resizeTask %d %d %d %d %d",
                id, L, T, L + lebar, T + tinggi)
            sukses = sukses + 1
        end
    end
    if #perintah > 0 then
        local out = sh("su -c '" .. table.concat(perintah, "; ") .. "' 2>&1") or ""
        if out:lower():find("unknown command") or out:lower():find("exception") then
            sukses, gagalPertama = 0, "ROM gak dukung 'am task resizeTask'"
        end
    end
    -- v4.27: sertain ukuran+orientasi biar gampang dicek kalau hasilnya meleset
    local info_layar = string.format("%dx%d %s", W, H, (W >= H) and "landscape" or "portrait")
    return sukses, (sukses == 0 and gagalPertama or nil), kol, bar, info_layar
end

function baca_ram()
    local mi = sh("cat /proc/meminfo")
    local total = tonumber(mi:match("MemTotal:%s+(%d+)")) or 0
    local avail = tonumber(mi:match("MemAvailable:%s+(%d+)")) or 0
    local gb = function(kb) return math.floor(kb/1024/1024*10+0.5)/10 end
    return gb(total-avail), gb(avail), gb(total)
end

-- ============================================================
-- v4.38: BACA DIALOG ERROR ROBLOX (Disconnected / Error Code 277 dst)
-- Kalau Roblox kelempar dari server, dialognya nongol TAPI activity-nya tetep
-- MainGameActivity -- jadi pkg_running tetep bilang "jalan" & worker gak sadar.
-- Satu-satunya cara liat isinya: dump UI. uiautomator cuma bisa baca jendela
-- yang lagi DI DEPAN, makanya client-nya dibawa ke depan dulu.
-- MAHAL (bawa ke depan + dump), jadi cuma dipanggil pas bridge udah CURIGA diem.
-- ============================================================
-- v4.39: SEMUA kode error Roblox ketangkep (formatnya selalu "Error Code: NNN"),
-- tapi penanganannya BEDA-BEDA. Asal masuk ulang buat semua error itu bahaya:
-- kode 268 justru artinya "kebanyakan nyoba" -- diulang malah makin diblok.
ERROR_SIFAT = {
    -- masuk ulang langsung: koneksi putus / kelempar biasa
    [260]="ulang", [261]="ulang", [262]="ulang", [269]="ulang", [270]="ulang",
    [272]="ulang", [273]="ulang", [277]="ulang", [279]="ulang", [280]="ulang",
    [291]="ulang", [292]="ulang", [773]="ulang",  -- 773: teleport ke place restricted
    -- backoff dulu: server/akun lagi dibatesin, buru-buru = makin parah
    [264]="tunggu",   -- akun yang sama join di tempat lain
    [268]="tunggu",   -- kebanyakan percobaan (rate limit)
    [529]="tunggu",   -- layanan Roblox lagi ngadat
    [517]="tunggu",   -- server lagi dimatiin
    -- v6.72: 524 -> "ulang" (masuk kembali). User minta coba lagi -- 524 sering
    -- muncul sementara (link PS baru di-assign belum sync), rejoin biasanya beres.
    [524]="ulang",    -- gak diizinin masuk private server -> coba masuk lagi
    -- percuma diulang: butuh dibenerin manual
    [267]="manual",   -- di-kick script game
    [522]="manual",   -- place dibatesin
    [523]="manual",
}
ERROR_TANDA = {
    "Error Code", "Disconnected", "Reconnect",
    "lost connection", "kicked", "Please check your internet",
}
-- v4.40: Delta/loader BEKU. Bukan kode error, tapi sama macetnya: script gak
-- pernah jalan -> bridge diem selamanya -> dibangunin berkali-kali gak nolong.
-- AMAN dari salah tangkap: pengecekan ini CUMA jalan kalau bridge udah diem
-- bermenit-menit. Layar loading yang normal gak akan pernah kesini.
-- v4.42: penanda LAYAR HOME Roblox / popup verifikasi umur. Ini yang bikin
-- client "jalan" tapi gak pernah masuk game. Dikenali langsung dari layar,
-- jadi gak usah nunggu bridge diem 90 detik baru sadar.
-- v4.83: penanda LAYAR KEY SYSTEM Delta. Ini WAJIB dikenali sendiri, karena
-- dibunuh pun gak nyelesaiin apa-apa -- kuncinya tetep harus masuk. Dulu layar
-- key kebaca "Home"/"nyangkut" -> client di-kill terus, dan kalau lagi ngerjain
-- `velium key` bisa kepotong di tengah jalan.
-- CATATAN: daftar ini masih SEMENTARA (belum dicocokin ke dump layar asli).
-- Tambahin sendiri lewat config: key_tanda="Kata A,Kata B"
KEY_TANDA = {
    "platorelay", "Key System", "KeySystem", "Get Key", "Getting Key",
    "Copy Key", "Enter Key", "Paste Key", "Checkpoint", "key expired",
    "Delta Key", "Verify Key",
}
HOME_TANDA = {
    "Access to popular games", "check your age",
    "Discover", "Charts", "Marketplace",
    -- v4.83: "Unlock" DICABUT dari sini. Itu tombol yang lazim di halaman key,
    -- jadi layar key kebaca Home -> client dibunuh percuma.
}
NYANGKUT_TANDA = {
    "Loading", "Injecting", "Please wait", "Checking", "Verifying",
}
-- balikin: pesan, sifat ("ulang"/"tunggu"/"manual")
-- v4.84: bagian PENILAIAN dipisah dari bagian AMBIL DUMP.
-- Alasannya: perintah `velium intip` harus nunjukin penilaian yang PERSIS SAMA
-- kayak yang dipakai worker. Kalau logikanya disalin dua kali, cepat atau
-- lambat dua-duanya beda -- dan diagnosa jadi nyesatin.
function klasifikasi_layar(isi)
    -- sidik layar: buat banding "berubah apa nggak" antar-intipan
    local sidik = #isi
    for t in isi:gmatch('text="([^"]+)"') do sidik = sidik + #t end

    -- v6.51: CAPTCHA dicek PALING DULU. Penanda PASTI dari dump asli RF:
    -- resource-id "FunCaptcha"/"arkose-0"/"challenge-container", plus teks
    -- "Start Puzzle" / "not a bot" / "solve this challenge". Kalau kena ->
    -- "captcha" (dilaporin panel + client di-skip, GAK dibunuh/rejoin -- rejoin
    -- percuma, captcha butuh solve manual).
    do
        local low = isi:lower()
        if isi:find("FunCaptcha", 1, true) or isi:find("arkose", 1, true)
           or isi:find("challenge-container", 1, true)
           or low:find("start puzzle", 1, true)
           or low:find("not a bot", 1, true)
           or low:find("solve this challenge", 1, true)
           -- v6.54: "Verifying browser" / "Verifying you're..." = TAHAP AWAL
           -- sebelum puzzle muncul. Deteksi lebih DINI (Roblox lagi ngecek
           -- browser sebelum kasih captcha). Kena juga -> skip.
           or low:find("verifying browser", 1, true)
           or low:find("verifying you", 1, true) then
            return "CAPTCHA (verif bot)", "captcha", sidik
        end
    end

    -- v6.70: ERROR KICK "save data didn't load" (GAG kick karena data akun gak
    -- ke-load). Teks jelas kebaca. Handle: MASUK LAGI (sifat "ulang" = rejoin).
    -- Error sementara Roblox, rejoin biasanya beres.
    do
        local low = isi:lower()
        if low:find("save data didn't load", 1, true)
           or low:find("save data didnt load", 1, true)
           or low:find("your save data didn", 1, true)
           or (low:find("kicked by this experience", 1, true) and low:find("save data", 1, true)) then
            return "KICK (save data gagal load) -> masuk lagi", "ulang", sidik
        end
    end

    -- LAYAR KEY dicek PALING DULU. Halaman key sering nampilin kata yang sama
    -- kayak layar lain ("Verifying", "Unlock", "Checking") -- kalau dicek
    -- belakangan, keburu keklasifikasi salah terus dibunuh percuma.
    for _, tanda in ipairs(KEY_TANDA) do
        if isi:lower():find(tanda:lower(), 1, true) then
            return ("layar KEY Delta ('" .. tanda .. "')"), "manual", sidik
        end
    end

    -- v6.71: match case-insensitive (isi:lower). Dulu "[Ee]rror [Cc]ode" gak
    -- nangkep "ERROR CODE" (semua kapital, kayak teks kick asli) -> kode gak
    -- kebaca -> error kayak 773 gak ke-handle. Sekarang lower dulu.
    local kode = tonumber(isi:lower():match("error code:?%s*(%d+)"))
    if kode then
        local sifat = ERROR_SIFAT[kode] or "ulang"

        -- ============================================================
        -- !! CATATAN PENTING SEBELUM PERCAYA BLOK INI !!
        -- Di RedFinger, dump uiautomator NYARIS SELALU 0 teks buat layar
        -- Roblox (lihat v4.85 di bawah) -- jadi seluruh pencocokan pesan di
        -- sini JARANG kepanggil. Yang beneran nangkep client kelempar itu
        -- BRIDGE DIEM: script berhenti lapor -> lewat auto_rejoin_menit ->
        -- client ditutup-buka. Blok ini cuma nolong kalau suatu saat dump-nya
        -- beneran kebaca (ROM/Android lain).
        -- Jangan nyetel auto_rejoin_menit kegedean dengan asumsi blok ini
        -- yang bakal nangkep duluan -- dia kemungkinan besar gak jalan.
        --
        -- v5.67: 267 DILIAT ISINYA, bukan cuma kodenya.
        --
        -- 267 = "di-kick script game" -- itu payung, sebabnya beda-beda:
        --   anti-cheat / ban        -> ngulang malah makin parah  (manual)
        --   GAGAL MUAT DATA SIMPANAN -> ngulang justru OBATNYA    (ulang)
        --
        -- Yang kedua itu kejadian rutin di GAG, dan game-nya SENDIRI yang
        -- nyuruh masuk ulang: "Uh oh! Your save data didn't load right. This
        -- is usually a Roblox problem, not the game's fault! Please rejoin to
        -- try again."
        -- Dulu dua-duanya dianggap "manual", jadi client yang cuma gagal muat
        -- data nyangkut di dialog sampai ada yang mencet manual.
        --
        -- Sengaja dicocokin ke KALIMATNYA, bukan cuma kata "rejoin" -- biar
        -- pesan lain yang kebetulan ngandung kata itu gak ikut kena.
        if kode == 267 then
            local l = isi:lower()
            local gagalMuat = l:find("save data", 1, true)
                              or l:find("didn't load", 1, true)
                              or l:find("did not load", 1, true)
            if gagalMuat then
                sifat = "ulang"
                return ("Error 267 (gagal muat data -> masuk ulang)"), sifat, sidik
            end
        end

        return ("Error Code " .. kode), sifat, sidik
    end
    for _, tanda in ipairs(ERROR_TANDA) do
        if isi:lower():find(tanda:lower(), 1, true) then
            return tanda, "ulang", sidik
        end
    end
    for _, tanda in ipairs(NYANGKUT_TANDA) do
        if isi:find(tanda, 1, true) then
            return ("nyangkut di '" .. tanda .. "'"), "ulang", sidik
        end
    end
    for _, tanda in ipairs(HOME_TANDA) do
        if isi:find(tanda, 1, true) then
            local kenapa = (tanda == "Access to popular games" or tanda == "check your age")
                and "popup verifikasi umur" or "layar Home Roblox"
            return ("nyangkut di " .. kenapa), "home", sidik
        end
    end

    -- LAYAR KOSONG (putih polos / cuma logo): gak ada teks yang bisa dibaca ->
    -- bukan layar game (game selalu punya tombol/label).
    local nTeks = 0
    for t in isi:gmatch('text="([^"]+)"') do
        if t:match("%S") then nTeks = nTeks + 1 end
    end
    if nTeks <= 2 then
        -- v4.85 (BUKTI LAPANGAN): di RedFinger, layar Roblox NGGAK PERNAH nyisain
        -- teks yang kebaca uiautomator -- game, layar key, Home, loading, semuanya
        -- kebaca 0 teks. Dua potret dibanding (client bermasalah vs client SEHAT)
        -- hasilnya nyaris identik: 3497 vs 3487 byte, class & resource-id sama
        -- persis, dua-duanya punya web_overlay_layout. Roblox nggambar semuanya ke
        -- permukaan GL, uiautomator cuma liat cangkangnya.
        --
        -- Dulu keadaan ini divonis "loading beku" -> KILL. Artinya TIAP kali worker
        -- ngintip, vonisnya selalu sama, termasuk buat client yang lagi sehat --
        -- ngintipnya gak nambah informasi apa pun, cuma nambah keyakinan palsu.
        -- Itu sumber utama client kebunuh percuma.
        --
        -- Sekarang: GAK TAU ya bilang GAK TAU. Keputusannya diserahin ke jalur yang
        -- emang kebukti jalan -- bridge (script lapor apa nggak), didorong dulu 2x,
        -- baru dibunuh, dan itu pun kena jatah 3x/30 menit.
        return nil, nil, sidik
    end
    return nil, nil, sidik
end

-- ambil dump layar 1 client. balikin isi XML, atau nil + sebab.
function ambil_dump(cfg, pkg, mapLink, lewatiFokus)
    local dump = "/sdcard/velium_ui.xml"
    -- v4.89: dulu munculinnya pakai 'am start -d <link>'. Kalau client lagi GAK
    -- di dalam game (mis. layar key), link itu dieksekusi beneran -> client join
    -- sendiri. Sekarang cuma mindahin task, gak nyentuh isi aplikasinya.
    bawa_depan(pkg)
    os.execute("sleep 3")
    if not lewatiFokus then
        local fokus = sh("su -c 'dumpsys window | grep mCurrentFocus'") or ""
        if not fokus:find(pkg, 1, true) then return nil, "yang di depan bukan client ini" end
    end
    sh_silent("su -c 'rm -f " .. dump .. "'")
    sh_silent("su -c 'uiautomator dump " .. dump .. "'")
    local isi = sh("su -c 'cat " .. dump .. " 2>/dev/null'") or ""
    sh_silent("su -c 'rm -f " .. dump .. "'")
    if not isi:match("%S") then return nil, "dump gagal / kosong" end
    return isi
end

-- v6.58: cek captcha "maksa" -- bawa client ke depan, dump, cari penanda
-- captcha. GAK cek fokus ketat kayak ambil_dump (yang sering bikin nil kalau
-- client gak persis di depan). Ini yang bikin `velium captcha` manual berhasil
-- tapi cek loop (cek_error_ui) gagal. Global biar kepakai di loop.
-- v7.31: LOGCAT STREAMING (kayak Pandora). Nyalain `logcat` STREAMING ke file
-- di background (bukan `logcat -d` dump berkala yg telat). Roblox nulis
-- disconnect ke logcat REAL-TIME -> worker baca ekor file tiap ronde -> deteksi
-- disconnect -> rejoin CEPAT. Pandora pake cara ini (logcat plain jalan terus,
-- gak uiautomator). GLOBAL (batas 200 lokal).
DC_LOG = "/sdcard/velium_disconnect.log"   -- history disconnect (buat `velium logcat`)
LIVE_LOG = "/sdcard/velium_logcat_live.log" -- stream mentah logcat (di-tail worker)
DC_TERAKHIR = {}   -- anti-dobel history: teks -> true
LIVE_OFFSET = 0    -- posisi byte terakhir yg udah dibaca dari LIVE_LOG

-- nyalain logcat streaming ke file (sekali, di background). Idempotent: kalau
-- udah jalan (ada proses logcat nulis ke LIVE_LOG), gak nyalain lagi.
function mulai_logcat_stream()
    -- cek udah ada logcat streaming ke file kita belum
    local h = io.popen("su -c 'pgrep -f \"logcat -v threadtime\"' 2>/dev/null")
    local ada = h and h:read("*all") or ""
    if h then h:close() end
    if ada:match("%d") then return false end   -- udah jalan
    -- kosongin file lama + nyalain logcat streaming di background.
    -- -v threadtime: format ada PID (biar tau client mana). -b main: buffer utama.
    -- nohup + & : jalan terus walau shell induk mati.
    os.execute("rm -f " .. LIVE_LOG)
    os.execute("su -c 'nohup logcat -v threadtime -b main > " .. LIVE_LOG .. " 2>/dev/null &' >/dev/null 2>&1")
    LIVE_OFFSET = 0
    return true
end

-- baca baris BARU dari LIVE_LOG (sejak offset terakhir), cari disconnect/kick.
-- Balikin daftar { pkg, kode, teks } yang perlu rejoin. Sekaligus catat ke
-- history (DC_LOG) buat `velium logcat`. pidKe: pid -> nama client.
function baca_logcat_stream(cfg, pidKe)
    local f = io.open(LIVE_LOG, "r")
    if not f then return {} end
    f:seek("set", LIVE_OFFSET)
    local data = f:read("*all") or ""
    LIVE_OFFSET = f:seek()   -- posisi baru
    f:close()
    if data == "" then return {} end

    local perluRejoin = {}
    local seenPkg = {}   -- 1 client cukup 1x rejoin per batch
    local fh = io.open(DC_LOG, "a")
    for baris in data:gmatch("[^\n]+") do
        local low = baris:lower()
        -- baris disconnect/kick PENTING
        if low:find("disconnected from server") or low:find("networkclient:remove")
           or low:find("save data") or low:find("error code") or low:find("kicked")
           or low:find("client:disconnect") or low:find("teleport failed")
           or low:find("lost connection") or low:find("disconnect with") then
            local pid = baris:match("^%S+%s+%S+%s+(%d+)")
            local nama = (pid and pidKe and pidKe[pid]) or "?"
            local kode = baris:match("reason:%s*%a*:?%s*(%d+)") or ""
            local jenis = baris:match("%((%w+)%)") or ""
            -- catat history (buat velium logcat)
            if fh and not DC_TERAKHIR[baris] then
                DC_TERAKHIR[baris] = true
                local waktu = os.date("%Y-%m-%d %H:%M:%S")
                local inti = (baris:match("%[.*$") or baris):sub(1, 140)
                fh:write(string.format("%s | %s | kode=%s | %s | %s\n",
                    waktu, nama, kode ~= "" and kode or "-", jenis ~= "" and jenis or "-", inti))
                -- v8.36: LOG ke Termux tiap disconnect (user minta -- biar keliatan
                -- MENIT berapa client disconnect, gampang di-copy buat debug).
                info(("[DISCONNECT] %s | %s | kode=%s | %s")
                    :format(os.date("%H:%M:%S"), nama,
                        kode ~= "" and kode or "-", jenis ~= "" and jenis or "-"))
            end
            -- REJOIN: client yang kepetakan (bukan "?") + belum di batch ini.
            -- Kode 285 (DisconnectClientInitiated) = keluar sendiri/backgrounding.
            -- Tetep rejoin (client keluar game = harus masuk lagi), KECUALI kalau
            -- lagi di-diurus (captcha). Yang penting client balik ke game.
            if nama ~= "?" and not seenPkg[nama] then
                seenPkg[nama] = true
                perluRejoin[#perluRejoin+1] = { nama = nama, kode = kode ~= "" and kode or "-" }
            end
        end
    end
    if fh then fh:close() end
    -- jaga DC_TERAKHIR gak bengkak
    local cnt = 0
    for _ in pairs(DC_TERAKHIR) do cnt = cnt + 1 end
    if cnt > 800 then DC_TERAKHIR = {} end
    -- jaga LIVE_LOG gak bengkak (kalau > 5MB, reset stream)
    local fs = io.open(LIVE_LOG, "r")
    if fs then
        local sz = fs:seek("end"); fs:close()
        if sz and sz > 5*1024*1024 then
            os.execute("su -c 'pkill -f \"logcat -v threadtime\"' 2>/dev/null")
            os.execute("rm -f " .. LIVE_LOG)
            LIVE_OFFSET = 0
            mulai_logcat_stream()
        end
    end
    return perluRejoin
end

-- fungsi lama (dump berkala) -- dipertahanin buat kompatibilitas, tapi gak
-- dipanggil lagi (diganti streaming). Biarin biar `velium logcat` lama gak error.
function rekam_disconnect(cfg, pidKe)
    return 0
end

function cek_captcha_paksa(pkg)
    -- v6.65: cek 5x (jeda 3s). Captcha render BERTAHAP: loading (~6000 char) ->
    -- transisi (~8000) -> full (~13000+, ada FunCaptcha/Start Puzzle). Sekali/2x
    -- cek bisa kebetulan pas belum full. Cek 5x + tanda tambahan: kalau
    -- "fragment_webview" kebuka TAPI GAK ADA elemen game (surfaceview + activity
    -- game), itu = webview verif nutupin layar = kemungkinan captcha.
    sh_silent("su -c 'monkey -p " .. pkg .. " -c android.intent.category.LAUNCHER 1 2>/dev/null'")
    local kebaca = false
    for percobaan = 1, 5 do
        os.execute("sleep 3")
        sh_silent("su -c 'uiautomator dump /sdcard/capf.xml'")
        local ui = sh("su -c 'cat /sdcard/capf.xml 2>/dev/null'") or ""
        sh_silent("su -c 'rm -f /sdcard/capf.xml'")
        print("[paksa] " .. pkg:gsub("com%.roblox%.","") .. " #" .. percobaan .. " dump " .. #ui .. " char")
        if ui:match("%S") then
            kebaca = true
            local low = ui:lower()
            -- penanda PASTI (teks/id captcha)
            if ui:find("FunCaptcha", 1, true) or ui:find("arkose", 1, true)
               or ui:find("challenge-container", 1, true)
               or low:find("start puzzle", 1, true)
               or low:find("not a bot", 1, true)
               or low:find("solve this challenge", 1, true)
               or low:find("verifying browser", 1, true)
               or low:find("verifying you", 1, true) then
                return "CAPTCHA"
            end
            -- v6.73: SEKALIAN cek error KICK yang butuh REJOIN (save data gagal
            -- load / disconnect / teleport failed). Ini yang bikin "gak kebaca
            -- uiautomator" -- cek_error_ui cek fokus ketat, sering nil. cek paksa
            -- ini gak cek fokus -> kebaca. Balikin "REJOIN" biar caller masuk lagi.
            if low:find("save data", 1, true)
               or low:find("didn't load", 1, true)
               or low:find("did not load", 1, true)
               or low:find("please rejoin", 1, true)
               or low:find("teleport failed", 1, true)
               or (low:find("disconnected", 1, true) and low:find("kicked", 1, true)) then
                return "REJOIN"
            end
            -- v7.27: DETEKSI KODE ERROR NUMERIK (267, 773, 524, dll). Teks kick
            -- Roblox: "Error Code: 267" (kapital di layar). Dulu gak kedeteksi --
            -- dump cuma bilang "5433 char" tanpa ngasih tau error apa. Sekarang:
            -- kalau nemu "error code XXX", LAPORIN kodenya + balikin REJOIN biar
            -- dimasukin lagi (kalau kode-nya sifat "ulang").
            local kode = low:match("error code:?%s*(%d+)")
            if kode then
                print("[paksa] " .. pkg:gsub("com%.roblox%.","") .. " KENA ERROR CODE " .. kode)
                return "REJOIN"
            end
            -- teks kick umum tanpa kode (kicked/removed/lost connection)
            if low:find("you were kicked", 1, true)
               or low:find("lost connection", 1, true)
               or low:find("connection attempt failed", 1, true)
               or low:find("reconnect", 1, true) then
                print("[paksa] " .. pkg:gsub("com%.roblox%.","") .. " kena kick/disconnect (tanpa kode)")
                return "REJOIN"
            end
        end
    end
    if not kebaca then return nil end   -- gak kebaca sama sekali
    return ""   -- kebaca 5x tapi gak ada captcha/error
end

function cek_error_ui(cfg, pkg, mapLink)
    -- v4.84: tinggal ngerangkai dua bagian di atas. Dulu ambil-dump dan
    -- penilaian nyampur di sini, jadi `velium intip` gak bisa makai penilaian
    -- yang sama tanpa nyalin kodenya.
    local isi = ambil_dump(cfg, pkg, mapLink)
    if not isi then return nil end
    return klasifikasi_layar(isi)
end

-- sambungin ke deklarasi maju di atas (dipakai tunggu_bridge)
cek_layar = cek_error_ui

-- v4.52: JAGA DEPAN. Delta Lite kadang nguncup sendiri jadi gelembung; kalau
-- dibiarin, Roblox di dalemnya disconnect ~15 detik kemudian. 'am start' dengan
-- REORDER_TO_FRONT cuma MUNCULIN window yang udah ada (gak restart game), jadi
-- aman dipanggil berkala -- kalau window-nya udah nongol, ini gak ngefek apa-apa.
-- v4.63: satu panggilan su buat semua client (dulu satu-satu, tiap 10 detik).
-- 'cekJalan' dioper dari cache biar gak dumpsys ulang.
-- v4.89: JANGAN pakai link join di sini. Fungsi ini jalan tiap 15 detik; kalau
-- ada client yang lagi di layar key (belum masuk game), link-nya dieksekusi
-- beneran -> client join sendiri, berulang tiap 15 detik. Sekarang cuma
-- mindahin task ke depan: 1 panggilan su buat baca taskId semua client,
-- 1 lagi buat mindahin semuanya sekaligus.
function jaga_depan(cfg, mapLink, cekJalan)
    -- v7.14: DIAKTIFIN LAGI (user: error dulu bukan karena jaga_depan). Cara
    -- AMAN: pakai `monkey -p <pkg> LAUNCHER` buat bawa tiap client ke depan --
    -- ini GAK nge-tap koordinat layar (beda dari cara lama yang tap petak &
    -- sering meleset ke app lain -> bahaya). monkey cuma kirim intent LAUNCHER,
    -- app naik ke depan / bubble balik freeform. Aman, gak mencet apa-apa.
    -- Cepet (gak dumpsys, gak cek fokus). Dipanggil tiap jaga_depan_sec (3s).
    local list = split(cfg.pkgs)
    local n = 0
    for _, pkg in ipairs(list) do
        -- cuma client yang HIDUP (proses ada) yang dibawa depan. Yang mati biar
        -- diurus jalur lain (mati mendadak / reopen). cekJalan = cache pkg_running.
        local hidup
        if cekJalan ~= nil then hidup = cekJalan[pkg]
        else hidup = pkg_running(pkg) end
        if hidup then
            sh_silent("su -c 'monkey -p " .. pkg .. " -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1'")
            n = n + 1
        end
    end
    return n
end

-- v4.61: 'only' sekarang boleh: nil (semua), string (1 paket), atau TABEL
-- (beberapa paket sekaligus). Nutup itu murah -- nutup 3 client barengan
-- makan waktu sama kayak nutup 1. Dulu dipanggil satu-satu -> tiap panggilan
-- nunggu verifikasi mati sendiri-sendiri -> lambat banget kalau banyak.
-- v8.49: TUTUP CEPAT BARENGAN (buat STOP). GLOBAL (bukan local) biar gak nambah
-- local di main chunk (udah mepet 200). force-stop semua barengan (& bg) -> cepet.
function close_all_cepat(cfg, skipVerif)
    local list = split(cfg.pkgs)
    if #list == 0 then return 0 end
    setAksi("STOP -- nutup semua client barengan")
    local cmd = "su -c '"
    for _, pkg in ipairs(list) do cmd = cmd .. "am force-stop " .. pkg .. " & " end
    cmd = cmd .. "wait'"
    sh_silent(cmd)
    info(("STOP: %d client ditembak tutup barengan"):format(#list))
    -- v8.59: skipVerif -> langsung balik (gak nunggu loop verifikasi 5s). Buat
    -- GRID: toh langsung buka ulang, gak perlu mastiin mati 100% dulu. STOP tetep
    -- verifikasi (mastiin bener-bener tutup).
    if skipVerif then return #list end
    local belum = {}
    for _, pkg in ipairs(list) do belum[pkg] = true end
    for _ = 1, 5 do
        os.execute("sleep 1")
        local adaHidup = false
        for pkg in pairs(belum) do
            local o = sh("su -c 'pidof " .. pkg .. "'")
            if not o:match("%d") then belum[pkg] = nil
            else adaHidup = true; sh_silent("su -c 'am force-stop " .. pkg .. "'") end
        end
        if not adaHidup then break end
    end
    return #list
end

-- v8.49: CEK STOP dari panel (deteksi cepet, dipanggil awal loop). Tutup client
-- barengan. Return true kalau STOP baru diproses. GLOBAL (gak nambah local main).
function cek_stop_panel(cfg, isi)
    if not isi or not isi:upper():find("STOP") then return false end
    if KICK_DIURUS["stop_killed"] then return false end
    warn("STOP dari panel -> tutup SEMUA client BARENGAN (cepet)")
    ok("STOP: " .. close_all_cepat(cfg) .. " client ditutup. Pencet Start buat mulai fresh.")
    KICK_DIURUS["stop_killed"] = true
    SUDAH_GRID = false
    for _, p in ipairs(split(cfg.pkgs or "")) do
        KICK_DIURUS["offlama:" .. p] = nil
        KICK_DIURUS["diag:" .. p] = nil
    end
    return true
end

function close_all(cfg, only, mapLink, tanpaMunculin)
    local list = split(cfg.pkgs)
    local mau = nil
    if type(only) == "table" then
        mau = {}
        for _, p in ipairs(only) do mau[p] = true end
    end
    local target = {}
    for _, pkg in ipairs(list) do
        if (not only) or (mau and mau[pkg]) or (type(only) == "string" and pkg == only) then
            target[#target+1] = pkg
        end
    end
    if #target == 0 then return 0 end
    setAksi(#target == #list and "nutup semua client"
            or ("nutup " .. #target .. " client"))
    -- v7.86: force-stop SATU-SATU + JEDA (kayak Pandora, dari logcat: tiap client
    -- jeda ~6-7s). Dulu force-stop SEMUA BARENG -> App Cloner service (Persistent
    -- AppService) keteteran -> NGERUSAK client lain. Pandora satu-satu biar service
    -- restart bersih tiap client. v8.03: jeda 5s (naik dari 3s -- 3s kurang, service
    -- belum bersih. 7s ideal tapi x10 client kelamaan, 5s kompromi).
    for _, pkg in ipairs(target) do
        sh_silent("su -c 'am force-stop " .. pkg .. "'")
        info("tutup paksa: " .. pkg)
        os.execute("sleep 5")   -- jeda tiap client (App Cloner service napas)
    end
    -- v4.19: FASE 2 -> tungguin SEMUA beneran mati PARALEL (bukan per-client 8s).
    -- penting buat pindah server: am start pas app masih idup -> Roblox abaikan
    -- (udah di server lama, gak pindah). tunggu sampai proses beneran mati.
    local belum = {}
    for _, pkg in ipairs(target) do belum[pkg] = true end
    for _ = 1, 8 do   -- max ~8 detik TOTAL (bukan per-client)
        os.execute("sleep 1")
        local adaHidup = false
        for pkg in pairs(belum) do
            local o = sh("su -c 'pidof " .. pkg .. "'")
            if not o:match("%d") then
                belum[pkg] = nil
            else
                adaHidup = true
                sh_silent("su -c 'am force-stop " .. pkg .. "'")   -- gedor lagi
            end
        end
        if not adaHidup then break end
    end
    local gagalTutup = 0
    for pkg in pairs(belum) do
        warn(pkg .. " MASIH IDUP setelah force-stop")
        gagalTutup = gagalTutup + 1
    end
    -- v4.56: kalau semua beneran mati, bilang -- biar gak dikira gagal diem-diem
    if gagalTutup == 0 and #target > 0 then
        info(("beneran ketutup: %d client"):format(#target))
    end
    os.execute("sleep 1")   -- napas ekstra biar sistem bersih

    -- v4.65: nutup SEBAGIAN bikin Android nyusun ulang tumpukan jendela --
    -- client yang GAK ditutup ikut kepental ke belakang (nyisa gelembung doang).
    -- Jadi begitu selesai nutup, langsung munculin balik yang selamat.
    -- v4.72: 'tanpaMunculin' dipakai kalau abis ini client-nya mau DIBUKA lagi.
    -- Munculin jendela lain di situ percuma -- beberapa detik kemudian ketimpa
    -- lagi sama client yang baru kebuka.
    if only ~= nil and #target < #list and not tanpaMunculin then
        local sisa = {}
        for _, pkg in ipairs(list) do
            local ikutDitutup = false
            for _, t in ipairs(target) do
                if t == pkg then ikutDitutup = true break end
            end
            if not ikutDitutup then sisa[#sisa+1] = pkg end
        end
        if #sisa > 0 then
            local hidup = pkg_running_semua(sisa)
            local bagian = {}
            for _, pkg in ipairs(sisa) do
                if hidup[pkg] then
                    local url = build_url(cfg, mapLink and mapLink[pkg] or nil)
                    bagian[#bagian+1] = "am start -f 0x20000000 -a android.intent.action.VIEW -d '"
                                        .. url .. "' -p " .. pkg
                end
            end
            if #bagian > 0 then
                sh_silent('su -c "' .. table.concat(bagian, "; ") .. '"')
                info(("%d client lain dimunculin balik"):format(#bagian))
            end
        end
    end
    return #target
end

-- cek_batal: dipanggil di sela-sela client. Buka 10 client bisa makan
-- 5-10 menit; tanpa ini, STANDBY dari panel gak kebaca sampe semuanya kelar.
TERAKHIR_BUKA = {}   -- v4.68: pkg -> kapan terakhir dibuka worker
function open_all(cfg, only, cek_batal, lapor_fn, mapLink, mapAkun, fast, paksaMasuk)
    -- v8.18: `only` bisa STRING (1 pkg, lama) ATAU TABLE {pkg=true,...} (banyak
    -- client dari FORCE:akun1,akun2). Helper: pkg ini termasuk yang mau dibuka?
    -- v9.121: ROTASI nyala -> loop buka/restart CUMA tim 1 (10 pkg pertama). Tim 2
    -- (11-20) dibuka via buka_grup_rotasi (am start langsung, bypass pilihPkg ini).
    -- Tanpa ini, loop "buka client belum jalan" periodik buka tim 2 (harusnya standby).
    local rotTim1 = nil
    if cfg.rotasi_on then
        rotTim1 = {}
        local lRot = split(cfg.pkgs)
        for i = 1, math.min(TIM1_AKHIR, #lRot) do rotTim1[lRot[i]] = true end
    end
    local function pilihPkg(pkg)
        if rotTim1 and not rotTim1[pkg] then return false end   -- rotasi: skip tim 2
        if not only then return true end            -- gak ada filter -> semua
        if type(only) == "table" then return only[pkg] == true end
        return pkg == only                          -- string tunggal (lama)
    end
    local list = split(cfg.pkgs)
    local hasil = { ok = 0, gagal = 0, lewat = 0, nama_gagal = {} }
    local urut = 0
    -- v7.12: TEMBAK BARENGAN. Kalau lisensi Delta ADA (gak perlu bypass key),
    -- buka semua client CEPET: open_one + tata grid, TANPA nunggu tiap client
    -- masuk game (tunggu_jalan pendek, gak bunuh-ulang nyangkut). Yang nyangkut
    -- Home ketangkep cek berkala/dump (tiap 90s) -> dimasukin. User minta: pas
    -- awal Start gak usah 1-1 nungguin, tembak semua bareng. lisensiAda di-set
    -- pas cek lisensi di bawah.
    local lisensiAda = false

    -- v9.294: ARCEUS gak pakai lisensi Delta (executor BEDA -- gak ada layar
    -- "Enter key" Delta, gak ada berkas kunci Delta). Langsung anggap lisensiAda=true
    -- -> skip semua cek + bypass Delta -> Arceus full fitur (grid, tembak barengan,
    -- stagger 30s). Kalau tetep dicek Delta, Arceus bisa nyangkut / kurang fitur.
    local arceusMode = (cfg.executor == "arceus")
    if arceusMode then lisensiAda = true end

    -- v8.28: CEK KEY juga di jalur FAST. Dulu lisensiAda cuma di-set di
    -- `if not fast and not only` -- kalau FORCE masuk lewat fast=true,
    -- lisensiAda tetep false -> masuk cabang "tutup dulu client" (close_all)
    -- tiap FORCE, walau client udah jalan + key ada. Bikin client di-close
    -- terus percuma. Fix: cek key langsung dari file di awal (lepas dari fast).
    do
        local kd = lisensi_keadaan(cfg)
        if kd == "ada" or cfg.auto_key ~= true then lisensiAda = true end
    end

    -- ============================================================
    -- v5.46: CEK LISENSI DELTA DULU, SEBELUM BUKA SEMUA CLIENT.
    --
    -- Dulu bypass dijalanin di loop utama -- ARTINYA setelah semua client
    -- kebuka. Akibatnya keempat client nyangkut bareng di layar "Enter key",
    -- makan RAM & CPU percuma, dan baru dibypass belakangan.
    --
    -- Berkas lisensinya ada di /sdcard dan dipakai BARENG semua client (verif
    -- Delta itu per-DEVICE, bukan per-instance). Jadi urutan yang bener:
    --   1. cek lisensi
    --   2. kalau hilang/basi -> buka SATU client, bypass, tulis kunci
    --   3. baru buka sisanya -- semuanya langsung lolos ke game
    --
    -- Kalau auto_key MATI (bawaan), bypass-nya gak dijalanin -- tapi
    -- peringatannya tetep muncul DI DEPAN, bukan setelah 4 client nyangkut.
    -- Itu sendiri udah nolong: dulu gejalanya cuma "client kebuka tapi diem".
    -- ============================================================
    -- v8.66 FIX: cek lisensi jalan walau `only` ada isinya (FORCE:daftar-akun =
    -- start sebagian client). Dulu syarat "not only" bikin cek lisensi DI-SKIP pas
    -- start sebagian -> client kebuka DULUAN (0/6...) tanpa cek lisensi -> nyangkut
    -- di layar key -> baru bypass di TENGAH sesi. Lisensi Delta itu per-DEVICE
    -- (semua client share), jadi HARUS dicek dulu apapun modenya (full/sebagian).
    if not fast and not arceusMode then
        local kead, umur = lisensi_keadaan(cfg)
        -- v7.14: tembak barengan kalau GAK PERLU BYPASS KEY. Itu berarti:
        -- lisensi ADA, ATAU auto_key MATI (worker gak ngurus key -> gak ada
        -- fase bypass yang butuh urutan). Cuma lisensi HILANG + auto_key NYALA
        -- (bener2 mau bypass) yang perlu sabar (client 1 dulu buat ambil key).
        if kead == "ada" or cfg.auto_key ~= true then lisensiAda = true end

        -- ============================================================
        -- v5.50: BERKAS BILANG "ADA" BELUM TENTU LISENSINYA SAH.
        --
        -- lisensi_keadaan() nebak dari UMUR BERKAS pakai key_jam (bawaan 24
        -- jam) -- dan angka itu masih TEBAKAN, belum pernah diukur. Kalau masa
        -- berlaku kunci Delta aslinya lebih pendek, berkasnya kebaca "ada"
        -- padahal Delta udah minta key lagi. Gejalanya: client kebuka, layar
        -- "Enter key" nongol, worker bilang gak ada masalah.
        --
        -- Layar RF gak bisa dibaca teksnya (v4.86), jadi dipakai sinyal
        -- PERILAKU: client yang JALAN tapi script-nya GAK PERNAH LAPOR.
        --
        -- Kenapa sinyal ini sah di sini: pemeriksaan ini jalan SEBELUM client
        -- dibuka. Jadi client yang kedapetan jalan itu sisa dari ronde
        -- SEBELUMNYA -- dia udah dapet waktu satu ronde penuh (reopen_sec,
        -- bawaan 300 detik) buat lapor. Kalau sampai sekarang belum, ada yang
        -- ngeblok, dan layar key itu penyebab paling umum.
        -- ============================================================
        -- v5.62: heuristik "client bisu" cuma berlaku kalau lisensinya UDAH
        -- CUKUP TUA. Ini pembatas yang v5.50 lupa dipasang, dan akibatnya
        -- positif palsu: lisensi umur 9 MENIT dicurigai basi cuma gara-gara
        -- ada 1 client yang belum lapor -- terus semua client ditutup dan
        -- bypass dijalanin percuma.
        --
        -- Kenapa gerbang ini sah: masa berlaku kunci Delta gak mungkin cuma
        -- semenit-dua menit -- kalau iya, seluruh pendekatan bypass ini gak
        -- ada gunanya. Jadi di bawah ambang ini, berkasnya DIPERCAYA.
        --
        -- Dan "client jalan tanpa lapor" itu sinyal yang LEMAH -- sebabnya
        -- banyak: masih loading, panel gak kejangkau, atau (yang kejadian
        -- di sini) nama berkas loader-nya salah jadi script gak pernah jalan.
        -- Heuristik ini cuma jaring pengaman buat kasus key_jam kegedean,
        -- bukan penentu utama.
        -- v5.96: heuristik "client bisu -> curiga lisensi" DIBUANG.
        -- Sekarang lisensi_keadaan() cek ISI file (FREE_<hash>) langsung --
        -- kalau isinya ada, key PASTI valid, gak peduli client bisu.
        -- Client bisu sebabnya lain (loading/lapor telat/loader salah nama),
        -- BUKAN key habis. Dulu heuristik ini bikin positif palsu: lisensi
        -- sehat -> tutup semua + bypass percuma. Cek isi jauh lebih andal.
        -- kead di sini udah "ada" atau "hilang" dari cek isi -- dipercaya.

        if kead ~= "ada" then
            local ket = (kead == "hilang") and "HILANG"
                        or (kead == "curiga") and "CURIGA (client bisu)"
                        or ("BASI (" .. umur_ringkas(umur) .. ")")
            warn("Lisensi Delta " .. ket .. " -- client bakal nyangkut di layar key.")

            -- v9.77: lisensi HILANG -> bypass WAJIB diutamain. Buang throttle 300s
            -- (dulu: bypass baru <5menit lalu -> SKIP -> langsung buka client ->
            -- nyangkut di layar key). Sekarang: lisensi ilang = bypass DULU, titik.
            local bypassSukses = false
            if cfg.auto_key == true then
                BYPASS_TERAKHIR = os.time()
                info("  bypass DULU (diutamain) -- semua client ditutup, mulai dari nol")

                -- ============================================================
                -- v5.58: TUTUP SEMUA CLIENT DULU, baru bypass.
                --
                -- Dulu client lain (yang statusnya latar/beku) dibiarin nyala
                -- selama bypass. Dua masalahnya:
                --   1. RAM kebagi. Di RF 4GB dengan 3 client nyala, sisa buat
                --      client bypass tinggal sedikit -- loading game jadi lama
                --      atau malah gak nyampe, dan deteksi grafis gagal.
                --   2. Client-client itu nyangkut di layar key juga -- gak ada
                --      gunanya nyala, cuma makan tenaga.
                -- Sekarang: bersihin semua, bypass sendirian dengan RAM penuh,
                -- baru buka semua dari [1/4] kayak biasa.
                -- ============================================================
                do
                    local potretAwal = pkg_running_semua(list)
                    local nyala = 0
                    for _, p in ipairs(list) do if potretAwal[p] then nyala = nyala + 1 end end
                    if nyala > 0 then
                        info(("  tutup %d client yang nyala biar RAM lega buat bypass..."):format(nyala))
                        -- v8.79: pakai close_all_cepat (tembak barengan, cepet) bukan
                        -- close_all (satu-satu 5s/client -- lama). User: tutup paksa pas
                        -- bypass lama banget beda 5s, gak kayak STOP yg cepet barengan.
                        close_all_cepat(cfg)
                        os.execute("sleep 3")
                    end
                end

                -- v8.91: pilih client yg COOKIE-nya NORMAL buat ambil key. Bug user:
                -- bypass ambil list[1] asal -- kalau cookie-nya ke-BAN/mati, client
                -- gak bisa masuk game -> gak bisa ambil key. Cek cookie tiap client,
                -- pilih yg PERTAMA normal (alive). Kalau semua gagal cek -> list[1].
                local pilih = nil
                do
                    local function cookie_pkg(pkg)
                        local db = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
                        -- v8.93: path sqlite3 LENGKAP (Termux). Bug: cuma "sqlite3"
                        -- gagal di su (PATH gak include) -> cookie kosong -> skip cek
                        -- -> fallback list[1] (cookie ban). Path lengkap = kebaca.
                        local cmd = ("su -c %s 2>/dev/null"):format(shq(
                            "/data/data/com.termux/files/usr/bin/sqlite3 " .. db ..
                            " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\""))
                        local h = io.popen(cmd)
                        local c = h and h:read("*all") or ""
                        if h then h:close() end
                        return cookie_terpanjang(c or "")
                    end
                    -- v9.50: pilih dari client AKTIF (only/PKGS_AKTIF), bukan semua 10.
                    -- Bug: bisa pilih client 7-10 (gak aktif) buat ambil key.
                    local listBypass = list
                    if only and type(only) == "table" then
                        listBypass = {}
                        for _, p in ipairs(list) do if only[p] then listBypass[#listBypass+1] = p end end
                        if #listBypass == 0 then listBypass = list end
                    elseif PKGS_AKTIF and #PKGS_AKTIF > 0 then
                        listBypass = PKGS_AKTIF
                    end
                    for _, pkg in ipairs(listBypass) do
                        local ck = cookie_pkg(pkg)
                        if ck and ck ~= "" then
                            local kead = cek_cookie_roblox(ck)
                            if kead == "alive" then
                                pilih = pkg
                                info("  pakai " .. pkg:gsub("com%.roblox%.","") .. " buat ambil key (cookie normal)")
                                break
                            else
                                info("  " .. pkg:gsub("com%.roblox%.","") .. " cookie " .. tostring(kead) .. " -> skip, cari yg normal...")
                            end
                        end
                    end
                    -- gak ada yg kebukti normal -> pakai listBypass[1] (fallback)
                    if not pilih then
                        pilih = listBypass[1]
                        info("  gak ada cookie kebukti normal -> pakai " .. pilih:gsub("com%.roblox%.","") .. " (fallback)")
                    end
                end

                -- v8.76: PAKSA tutup client pilihan dulu (walau kira udah mati).
                -- Bug user: client bypass masih UKURAN LAMA (6-client, 533x360)
                -- padahal prefs 10-client udah ditulis. Sebabnya: App Cloner cuma
                -- baca prefs posisi pas app START DARI MATI TOTAL. Kalau proses masih
                -- nyangkut (kedeteksi "mati" tapi sebenernya idup), open_one cuma
                -- bawa depan -> posisi lama kepakai. Tutup paksa dulu -> pasti fresh.
                pcall(function()
                    sh_silent("su -c 'am force-stop " .. pilih .. "'")
                end)
                os.execute("sleep 2")

                -- buka dia sendirian biar layar key-nya nongol.
                -- (v5.58: gak ada lagi cabang "udah jalan" -- semua udah
                -- ditutup di atas, jadi keadaannya selalu sama. Dulu ada dua
                -- cabang dan yang satu bikin jendelanya kepakai petak lama.)
                do
                    -- v5.46b: DIBUKA DI PETAK GRID-nya, bukan jendela penuh.
                    -- Alasannya: kalibrasi tombol (velium_tap.txt) dikunci per
                    -- UKURAN JENDELA -- "396x293 0.823 0.723" dst. Ukuran grid
                    -- itu yang udah kebukti kena. Maksa jendela penuh bikin
                    -- ukurannya jadi baru, kalibrasinya gak kepakai, dan worker
                    -- harus nyapu ulang -- padahal gak perlu.
                    -- Jendela penuh tetep dipakai, TAPI cuma kalau deteksi di
                    -- ukuran grid gagal (lihat di bawah).
                    -- v8.94: pakai grid AKTIF (PKGS_AKTIF) buat posisi client bypass,
                    -- BUKAN paksa 10 client. User udah kalibrasi titik key buat layout
                    -- aktif (mis. 6 client = 396x330 = 0.833,0.675). Titik key dibaca
                    -- dari tap_muat()[ukuran] -> asal client diposisikan di grid aktif,
                    -- ukuran jendela match kalibrasi -> titik kena. Konsisten sama grid
                    -- yg keliatan (open_all). Gak perlu paksa 10 lagi.
                    -- v9.49: grid bypass pakai 'only' (param open_all, client yg
                    -- MAU dibuka) konversi ke list, BUKAN PKGS_AKTIF global (bisa
                    -- stale/nil -> grid dihitung buat 10 = 4x3, client bypass kecil).
                    -- Bug user: pas bypass client jadi 4x3 padahal 6. Fix: pakai only.
                    local pkgsBypass = nil
                    if only and type(only) == "table" then
                        pkgsBypass = {}
                        for _, p in ipairs(split(cfg.pkgs)) do
                            if only[p] and not rotasi_lewat(cfg, p) then pkgsBypass[#pkgsBypass+1] = p end
                        end
                        if #pkgsBypass == 0 then pkgsBypass = nil end
                    end
                    if not pkgsBypass and PKGS_AKTIF and #PKGS_AKTIF > 0 then
                        pkgsBypass = PKGS_AKTIF
                    end
                    local petaK = grid_hitung(cfg, pkgsBypass)
                    if petaK and petaK[pilih] then
                        -- hapusDulu=true: buang posisi lama biar bener2 pas di grid aktif
                        local tok, tket = tata_satu(pilih, petaK[pilih], true)
                        if tok and tket ~= "udah pas" then
                            info("  posisi jendela " .. pilih:gsub("com%.roblox%.", "") .. " (grid aktif): " .. tket)
                        end
                    end
                    info("  buka " .. pilih:gsub("com%.roblox%.", "") .. " buat ambil link key...")
                    open_one(cfg, pilih, mapLink and mapLink[pilih] or nil, "start-bypass")
                    tunggu_jalan(pilih, tonumber(cfg.wait_sec) or 60, cek_batal, cfg, mapLink and mapLink[pilih] or nil)
                    -- v5.57: nunggu SINYAL, bukan nebak waktu. tunggu_jalan
                    -- cuma mastiin activity Roblox nongol -- dan itu udah kena
                    -- di halaman awal. Yang nandain beneran masuk game itu
                    -- MEMORI GRAFIS naik tajam (ukur lapangan: 15 -> 49 MB).
                    local msk, lama, sbb = tunggu_masuk_game(pilih, 150, cek_batal)
                    if msk then
                        ok(("  masuk game setelah %ds -- dialog key bentar lagi nongol"):format(lama))
                        -- v6.12: dialog Delta nongol 10-20 DETIK setelah masuk game
                        -- (ukur lapangan). Dulu cuma sleep 8 -> tap pas dialog
                        -- BELUM nongol -> kena kosong. Naikin ke 18 detik biar
                        -- dialog udah muncul sebelum tap pertama. Loop sapu (jeda
                        -- 25s tiap putaran) tetep jadi jaring kalau masih telat.
                        info("  tunggu dialog key nongol (~18s)...")
                        for _ = 1, 18 do
                            if cek_batal and cek_batal() then break end
                            os.execute("sleep 1")
                        end
                    else
                        warn("  gak kedeteksi masuk game (" .. tostring(sbb) .. ")")
                        info("  lanjut aja -- sapuan tetep dicoba beberapa putaran")
                    end
                end

                -- ============================================================
                -- v5.52: SAPUAN DICOBA BEBERAPA PUTARAN, bukan sekali habis.
                --
                -- Masalahnya: dialog key Delta baru muncul SETELAH game kebuka.
                -- Dulu sapuan mulai cuma 3 detik setelah tunggu_jalan bilang
                -- "udah jalan" -- padahal saat itu client masih di halaman awal
                -- Roblox (kebukti dari layar: Search/Charts/Avatar). 16 titik
                -- dihabisin buat dialog yang belum ada, terus dilaporin gagal.
                --
                -- Activity gak bisa dipakai buat mastiin: ActivityNativeMain &
                -- MainGameActivity itu nama LAMA vs BARU buat activity yang SAMA
                -- (v4.36) -- halaman awal dan di-dalam-game satu activity, gak
                -- ada bedanya di mata dumpsys. Teks layar juga gak kebaca (v4.86).
                --
                -- Deteksinya akhirnya ketemu di v5.63: MEMORI GRAFIS naik tajam
                -- (tunggu_masuk_game, dipanggil di atas). Putaran sapuan ini
                -- TETEP dipertahanin sebagai jaring: jeda antara "masuk game"
                -- dan "Delta nyuntik dialognya" gak pasti, dan kalau meminfo
                -- gak kebaca, deteksinya nyerah -- di situ putaran ini yang
                -- nutupin.
                -- ============================================================
                -- v6.09: PASTIIN JENDELA UDAH DI PETAK sebelum sapu. Masalah:
                -- pas bypass buka client, jendelanya FULLSCREEN dulu (1280x720)
                -- sebelum App Cloner naruh ke petak (290x330). Kalau sapu kebaca
                -- pas masih fullscreen -> kunci ukuran salah -> kalibrasi 290x330
                -- gak kepakai -> tebakan baris meleset -> sapu belasan titik.
                -- Fix: tunggu + tata ke petak, cek ukuran settle dulu.
                do
                    -- v9.172: BYPASS paksa petak 3x2 buat 6 CLIENT. Config punya 20
                    -- client -> grid_hitung 20 = banyak kolom = petak KEKECILAN
                    -- (152x210, gak kalibrasi -> sapu meleset). Bikin list 6 client
                    -- (pilih + 5 lain dari config), paksa 3 kolom -> petak 3x2 GEDE
                    -- (kalibrasi 396x330 dst -> sapu kena). Client lain gak keganggu
                    -- (cuma jendela bypass yg ditata sementara).
                    local enam = { pilih }
                    for _, p in ipairs(split(cfg.pkgs)) do
                        if p ~= pilih and #enam < 6 then enam[#enam+1] = p end
                    end
                    local kolAsli = cfg.grid_kolom
                    -- v9.241: grid_kolom sekarang = BARIS (bukan kolom). Bypass mau 6 client
                    -- jadi 3x2 (3 kolom x 2 BARIS) biar tombol key di posisi 2-baris (Y 0.723).
                    -- Jadi set BARIS=2 (bukan 3). 6 client / 2 baris = 3 kolom -> 3x2. Bener.
                    cfg.grid_kolom = 2
                    local petaP, _gh_err, kolP, barP, wLayar, hLayar = grid_hitung(cfg, enam)
                    cfg.grid_kolom = kolAsli   -- balikin (jangan ganggu grid utama)
                    -- v9.171: LOG diagnosa -- layar + grid + jumlah client dipaksa
                    do
                        info(("  [bypass-grid] layar %dx%d | grid %dx%d | PAKSA 6 client 3x2"):format(
                            wLayar or 0, hLayar or 0, kolP or 0, barP or 0))
                    end
                    if petaP and petaP[pilih] then
                        local tgt = petaP[pilih]
                        local tgtW, tgtH = tgt.R - tgt.L, tgt.B - tgt.T
                        for coba = 1, 3 do
                            local k = jendela_kotak(pilih)
                            local lebar  = k and (k.R - k.L) or 0
                            local tinggi = k and (k.B - k.T) or 0
                            -- match 3x2 (toleransi 15px, App Cloner kadang geser)
                            if lebar > 0 and math.abs(lebar - tgtW) <= 15 and math.abs(tinggi - tgtH) <= 15 then
                                info(("  jendela UDAH 3x2 (%dx%d) -- lanjut sapu"):format(lebar, tinggi))
                                break
                            end
                            -- v9.173: SPAM tata_satu PERCUMA -- App Cloner baca posisi
                            -- jendela cuma pas app OPEN (bukan pas jalan). Jadi harus:
                            -- tulis prefs 3x2 -> FORCE CLOSE -> buka ulang -> delay ->
                            -- cek ulang. Baru window pindah ke 3x2 beneran.
                            info(("  jendela %dx%d BUKAN 3x2 (target %dx%d) -- FORCE CLOSE + buka ulang 3x2 (%d/3)..."):format(
                                lebar, tinggi, tgtW, tgtH, coba))
                            tata_satu(pilih, tgt, true)              -- tulis prefs 3x2
                            sh(("su -c 'am force-stop %s' 2>/dev/null"):format(pilih))   -- force close
                            os.execute("sleep 3")                    -- kasih waktu bener2 mati
                            open_one(cfg, pilih, mapLink and mapLink[pilih] or nil, "bypass-3x2")   -- buka ulang
                            os.execute("sleep 8")                    -- App Cloner naruh jendela + mulai load
                            if cek_batal and cek_batal() then break end
                        end
                    end
                end

                local link, ketLink
                local PUTARAN, JEDA = 3, 25
                -- v6.06: ambang grafis "masih di game". Di bawah ini = kemungkinan
                -- balik ke Home (client kadang keluar game lagi setelah masuk).
                local GAME_MIN_KB = 25 * 1024   -- 25 MB (game ~30-49, home ~15)
                for putar = 1, PUTARAN do
                    if putar > 1 then
                        info(("  dialog key belum nongol -- tunggu %ds, sapu lagi (%d/%d)")
                            :format(JEDA, putar, PUTARAN))
                        for _ = 1, JEDA do
                            if cek_batal and cek_batal() then break end
                            os.execute("sleep 1")
                        end
                        if cek_batal and cek_batal() then break end
                    end

                    -- v6.06: CEK ULANG masih di game SEBELUM nyapu. Client kadang
                    -- keluar ke Home setelah masuk -- kalau gitu, titik key disapu
                    -- di layar kosong (Home) -> gagal. Jadi: cek grafis, kalau
                    -- turun (balik Home) -> masukin lagi ke game DULU, baru sapu.
                    local gnow = grafis_kb(pilih) or 0
                    if gnow < GAME_MIN_KB then
                        warn(("  client balik ke Home (grafis %.1f MB) -- masukin lagi ke game"):format(gnow/1024))
                        -- BUKA lagi (open_one) -- tunggu_masuk_game cuma NUNGGU,
                        -- gak masukin. Harus di-open_one dulu biar beneran masuk.
                        open_one(cfg, pilih, mapLink and mapLink[pilih] or nil, "balik-home-startup")
                        local msk2 = tunggu_masuk_game(pilih, 90, cek_batal)
                        if msk2 then
                            ok("  udah balik di game -- lanjut sapu titik")
                            os.execute("sleep 6")   -- kasih Delta nyuntik dialog lagi
                        else
                            info("  belum kedeteksi di game -- sapu tetep dicoba")
                        end
                        if cek_batal and cek_batal() then break end
                    end

                    link, _, _, ketLink = cari_tombol_key(cfg, pilih)
                    if link then break end
                end

                -- v5.64: CADANGAN "buka ulang jendela penuh" DIBUANG.
                -- Dulu kalau sapuan gagal, client ditutup lalu dibuka ulang
                -- FULLSCREEN dengan alasan "tombolnya jadi lebih gede".
                -- Itu salah arah: kalibrasi tombol (velium_tap.txt) dikunci per
                -- UKURAN JENDELA, dan ukuran petak grid itu yang udah kebukti
                -- kena. Jendela penuh = ukuran yang belum pernah dikalibrasi,
                -- jadi worker malah kehilangan koordinat yang udah pasti dan
                -- harus nyapu dari nol.
                -- Kalau sapuan gagal, yang bener itu NYAPU LAGI di petak yang
                -- sama (udah ditangani 3 putaran berjeda di atas), bukan ganti
                -- ukuran jendela.

                if link then
                    -- v9.77: RETRY bypass sampai 5x kalau gagal. User: kalau API
                    -- bypass gagal (mis. "Unknown error while bypassing"), JANGAN
                    -- lanjut loop lain -- tembak terus sampai 5x baru nyerah.
                    local kunci, sebab
                    for percobaan = 1, 5 do
                        kunci, sebab = bypass_kunci(cfg, link, percobaan > 1)  -- retry pakai refresh
                        if kunci then
                            if percobaan > 1 then ok("  BYPASS sukses di percobaan ke-" .. percobaan) end
                            break
                        end
                        warn(("  API bypass gagal (percobaan %d/5): %s"):format(percobaan, tostring(sebab)))
                        if percobaan < 5 then
                            info("  tunggu 8s -> tembak bypass lagi...")
                            os.execute("sleep 8")
                        end
                    end
                    if kunci then
                        local wok, wket = tulis_lisensi(cfg, kunci)
                        if wok then
                            ok("  BYPASS BERES -- kunci ketulis, kepakai SEMUA client")
                            lisensiAda = true   -- v7.16: key udah ada -> sisa client TEMBAK BARENGAN (cepet)
                            bypassSukses = true   -- v9.77: tandai sukses -> boleh lanjut buka client
                            -- v5.49: client yang dipakai buat ambil key DITUTUP.
                            -- Dia kebuka SEBELUM lisensinya ada, jadi sekarang
                            -- nyangkut di layar key -- lisensi baru gak kebaca
                            -- sama sesi yang udah jalan.
                            -- Ditutup biar dia ikut dibuka ULANG di urutan
                            -- normal ([1/4], [2/4], ...) dengan lisensi yang
                            -- udah ada -> langsung lolos ke game.
                            -- Kalau cuma ngandelin saringan "udah jalan" di
                            -- bawah, dia BISA kelewat: saringan itu ngecek
                            -- laporan bridge, dan akun ini mungkin masih punya
                            -- laporan segar dari sesi sebelum lisensi abis.
                            close_all(cfg, pilih, mapLink, true)
                            os.execute("sleep 2")
                            info("  " .. pilih:gsub("com%.roblox%.", "") ..
                                 " ditutup -- dibuka ulang bareng yang lain")
                        else
                            warn("  kunci dapet tapi gagal nulis: " .. tostring(wket))
                        end
                    else
                        warn("  API bypass NYERAH setelah 5x gagal: " .. tostring(sebab))
                        info("  coba manual: velium key")
                    end
                else
                    warn("  gagal nemu tombol key: " .. tostring(ketLink))
                    info("  coba manual: velium cari " .. pilih:gsub("com%.roblox%.", ""))
                end
            else
                if cfg.auto_key ~= true then
                    info("  auto_key MATI -> bypass gak dijalanin sendiri.")
                    info("  Jalanin sekarang:  velium key      (atau: auto_key=true di config)")
                end
            end
            -- v9.77: lisensi ilang + bypass GAK SUKSES -> JANGAN buka client (bakal
            -- nyangkut di layar key). Return early -> loop depan tembak bypass lagi.
            -- User: loop bypass wajib diutamain.
            if cfg.auto_key == true and not bypassSukses then
                warn("  bypass belum sukses -> TUNDA buka client (biar gak nyangkut layar key). Ronde depan bypass lagi.")
                return hasil
            end
        end
    end

    -- v4.17: /stat sekali di awal, buat cek "beneran di game" pas skip client.
    -- v4.19: fast=true (buat REJOIN ganti server) -> skip bridge-confirm biar CEPET,
    -- gak nunggu tiap client lapor 90s. cukup mastiin proses muncul.
    local stat0 = (not fast) and api_get(cfg, "/stat") or ""
    -- v4.82: petak dihitung SEKALI di awal, dari urutan cfg.pkgs (tetap) --
    -- bukan urutan buka, yang suka diacak (client stok habis didahuluin).
    -- v6.71: PAKSA LANDSCAPE dulu SEBELUM hitung grid. Kalau layar lagi portrait
    -- pas grid dihitung, layar_ukuran() baca W/H portrait -> susunan kacau (8
    -- client bisa jadi 1 baris kecil2). User mau SELALU landscape + grid rapi
    -- konsisten. Set rotasi landscape + tunggu 1 detik biar rotate kelar, baru
    -- baca ukuran. (accelerometer_rotation 0 = matiin auto-rotate biar gak balik.)
    sh("su -c 'settings put system accelerometer_rotation 0 >/dev/null 2>&1; " ..
       "settings put system user_rotation 1 >/dev/null 2>&1'")
    os.execute("sleep 1")
    local petaGrid = nil
    if cfg.auto_grid == true then
        -- v8.19: kalau `only` daftar client (FORCE:akun1,akun2), grid dihitung
        -- buat CLIENT ITU aja -> 2 client = 2 petak lebar, bukan 10 petak kecil.
        local pkgsGrid = nil
        if type(only) == "table" then
            pkgsGrid = {}
            for _, pkg in ipairs(split(cfg.pkgs)) do
                if only[pkg] then pkgsGrid[#pkgsGrid+1] = pkg end
            end
            if #pkgsGrid == 0 then pkgsGrid = nil end
        end
        -- v9.248: kalau GAK ada 'only' spesifik -> grid buat TIM 1 (1..TIM1_AKHIR) aja,
        -- BUKAN semua 20 client. Yang jalan di loop utama = tim 1 (10 client). Tim 2
        -- (11-20) grid-nya diitung TERPISAH pas batch borong. Dulu nil -> grid_hitung
        -- pake semua 20 -> grid 20 petak (kekecilan). Sekarang default 10 petak.
        if not pkgsGrid then
            local semua = split(cfg.pkgs)
            pkgsGrid = {}
            for i = 1, math.min(TIM1_AKHIR, #semua) do pkgsGrid[#pkgsGrid+1] = semua[i] end
            if #pkgsGrid == 0 then pkgsGrid = nil end
        end
        -- v9.252: BATASI grid startup ke TIM 1 (10). FORCE kirim 20 (all) -> only=20 ->
        -- pkgsGrid 20 -> grid 20-slot (kekecilan). "Set grid semua client" cuma buat
        -- tim 1 (yg jalan loop utama). Ambil client tim 1 (1..TIM1_AKHIR) dari pkgsGrid.
        if pkgsGrid and #pkgsGrid > TIM1_AKHIR then
            local semua = split(cfg.pkgs)
            local set1 = {}
            for i = 1, math.min(TIM1_AKHIR, #semua) do set1[semua[i]] = true end
            local t1 = {}
            for _, pkg in ipairs(pkgsGrid) do if set1[pkg] then t1[#t1+1] = pkg end end
            if #t1 > 0 then pkgsGrid = t1 end
        end
        local p, sebabGrid = grid_hitung(cfg, pkgsGrid)
        if p then petaGrid = p
        else warn("tata jendela dilewat: " .. tostring(sebabGrid)) end
        -- v8.92: SET PKGS_AKTIF = pkgsGrid biar grid_satu (rejoin) pakai layout
        -- SAMA. Bug user: grid CAMPUR (ada normal ada nggak) -- karena open_all
        -- pakai pkgsGrid tapi grid_satu pakai PKGS_AKTIF, kalau beda -> layout
        -- beda per client. Sekarang 1 sumber: pkgsGrid = PKGS_AKTIF.
        PKGS_AKTIF = pkgsGrid   -- nil (FORCE polos) = semua, sama kayak grid_hitung
    end
    -- v7.25: set grid CUMA kalau belum pernah (SUDAH_GRID false). Dulu jalan
    -- TIAP open_all -> force-stop SEMUA client tiap ronde FORCE -> semua keluar
    -- terus dibuka ulang (user liat "keluar semua"). SUDAH_GRID di-reset cuma
    -- pas FORCE transisi (Start baru), jadi grid keset sekali per sesi.
    if lisensiAda and petaGrid and not SUDAH_GRID then
        info("Set grid semua client sekali (tulis prefs, gak force-stop)...")
        for _, pkg in ipairs(list) do
            if petaGrid[pkg] then
                -- v7.38: JANGAN force-stop! Dulu force-stop SEMUA client hidup
                -- biar App Cloner langsung baca prefs -> tapi itu bikin MATI
                -- BARENGAN (client yang lagi main ke-kill). Kayak Pandora: cukup
                -- TULIS prefs posisi (tata_satu udah nulis ke shared_prefs).
                -- Client nyusul posisi pas restart NATURAL (rejoin/crash/buka).
                -- Yang lagi main gak keganggu -> gak ada mati bareng.
                tata_satu(pkg, petaGrid[pkg], true)   -- v8.67: hapus posisi lama dulu
            end
        end
        os.execute("sleep 1")
    elseif lisensiAda and petaGrid then
        -- v8.95: PENGAMAN EKSTRA. Walau SUDAH_GRID (grid udah keset sekali),
        -- tetep tulis ulang prefs posisi buat client yg mau dibuka. Bug user:
        -- kadang grid gak rapi -- prefs bisa ketimpa App Cloner pas client
        -- ditutup. Tulis lagi sebelum buka = jaminan posisi bener. Murah (tulis
        -- prefs, gak force-stop), gak ganggu yg lagi main.
        for _, pkg in ipairs(list) do
            if petaGrid[pkg] and not pkg_hidup(pkg) then   -- cuma yg mau dibuka (mati)
                tata_satu(pkg, petaGrid[pkg], true)
            end
        end
    end
    local stat0Ts = os.time()   -- v4.67: kapan potret /stat itu diambil
    local potretJalan = pkg_running_semua(list)   -- v4.71: sekali dumpsys buat semua
    local potretTs = os.time()
    local tunda = {}   -- v4.59: client yang nunggu konfirmasi bridge (dicek di akhir)
    set_orientasi(cfg)   -- v4.18: pastiin orientasi pas buka (jaga-jaga ke-reset)

    -- v4.64: DAHULUIN YANG STOKNYA HABIS. Client yang pet-nya tinggal dikit itu
    -- yang paling butuh masuk gudang leveling -- makin cepet dia masuk, makin
    -- cepet diisi. Yang stoknya masih tebal boleh belakangan; dia gak lagi
    -- nunggu apa-apa. Urutan dibaca dari /stat (petrule per akun).
    if not only and stat0 ~= "" then
        local stok = {}
        for pkg in pairs(mapAkun or {}) do
            local ak = mapAkun[pkg]
            local blok = ak and stat0:match('{[^{}]-"nama"%s*:%s*"' .. ak .. '"[^{}]-}')
            stok[pkg] = blok and tonumber(blok:match('"petrule"%s*:%s*(%d+)')) or nil
        end
        table.sort(list, function(a, b)
            local sa = stok[a] or math.huge      -- gak ketauan -> taro belakangan
            local sb = stok[b] or math.huge
            if sa ~= sb then return sa < sb end   -- paling kosong DULUAN
            return a < b                          -- biar urutannya tetap
        end)
    end

    if lisensiAda and not only and not fast then
        info(">> MODE TEMBAK BARENGAN (lisensi ok / auto_key mati) -- buka cepet, gak tutup dulu")
    end

    -- v7.39: PRA-HITUNG berapa client yang PERLU DIBUKA (yang keluar/gak jalan).
    -- Biar nomor progress bener: kalau cuma 3 yang keluar dari 10, tampil "1/3,
    -- 2/3, 3/3" (bukan "1/10" yang bikin bingung). Yang udah jalan & lapor sehat
    -- di-skip, gak masuk hitungan. Pakai saringan yang SAMA kayak di loop.
    local perluBuka = 0
    do
        local panelBuram0 = (ambil_num(stat0, "skrg") == nil)
        for _, pkg in ipairs(list) do
            if pilihPkg(pkg) then
                local akun = mapAkun and mapAkun[pkg]
                local baruDisentuh = TERAKHIR_BUKA[pkg] and
                                     (os.time() - TERAKHIR_BUKA[pkg]) < (cfg.konfirmasi_sec or 90)
                local lagiJalan = potretJalan and potretJalan[pkg]
                if lagiJalan == nil then lagiJalan = pkg_running(pkg) end
                local denyutFresh0 = akun and DENYUT_UMUR[akun] and DENYUT_UMUR[akun] <= 180
                local diLewat = lagiJalan and (panelBuram0 or not akun
                                or bridge_fresh(stat0, akun) or baruDisentuh or denyutFresh0)
                local diCaptcha = akun and KICK_DIURUS["captcha:" .. pkg]
                local diMati = akun and KICK_DIURUS["mati:" .. akun]
                if not diLewat and not diCaptcha and not diMati then
                    perluBuka = perluBuka + 1
                end
            end
        end
        if perluBuka > 0 and perluBuka < #list then
            info(("Perlu buka %d client (dari %d) -- sisanya udah jalan"):format(perluBuka, #list))
        end
    end
    local urutBuka = 0   -- nomor progress khusus yang DIBUKA (1/perluBuka)
    -- v9.133: ROTASI -> tembak SEMUA client yg perlu buka BARENGAN (buka_grup_rotasi),
    -- SKIP loop open_one 1-1 yg lambat (~70s/client: task-remove+sleep5+cek game).
    -- buka_grup_rotasi = grid all + am start batch (1 su call, jeda 1s) -> ~9s.
    if cfg.rotasi_on then
        local jalanMap = pkg_running_semua(list) or {}
        local perluRot = {}
        local aktifSemua = {}   -- v9.253: SEMUA client aktif (buat grid BASIS penuh)
        for _, pkg in ipairs(list) do
            if pilihPkg(pkg) then
                aktifSemua[#aktifSemua+1] = pkg
                if not jalanMap[pkg] then perluRot[#perluRot+1] = pkg end
            end
        end
        if #perluRot > 0 then
            info(("[rotasi] tembak BARENGAN %d client (bukan open_one 1-1)"):format(#perluRot))
            -- v9.253: gridBasis = aktifSemua (10) -> rejoin subset (7) TETEP grid 10-slot,
            -- posisi konsisten. Dulu grid pakai perluRot (7) -> 7-slot (beda ukuran).
            pcall(function() buka_grup_rotasi(cfg, perluRot, mapLink, 90, nil, aktifSemua) end)
        else
            info("[rotasi] semua client tim aktif udah jalan -- skip open")
        end
    else
    for _, pkg in ipairs(list) do
        if pilihPkg(pkg) then
            urut = urut + 1

            if cek_batal and cek_batal() then
                warn("perintah baru nyerobot -> berhenti buka (sisa dilewat)")
                break
            end

            local akun = (mapAkun and mapAkun[pkg]) or baca_username(pkg)

            -- v4.17: skip cuma kalau BENERAN di game = proses ADA + akun lapor fresh.
            -- dulu: skip kalau pkg_running aja -> client nyangkut di Home ke-skip
            -- selamanya (Home JUGA ActivityNativeMain). sekarang bridge yg mutusin.
            -- v4.67: SEGERIN data sebelum mutusin. Dulu potret /stat diambil
            -- SEKALI di awal open_all, padahal buka 4 client bisa makan menit-
            -- menitan -- pas giliran client ke-3/4, potretnya udah basi, jadi
            -- client yang BARU MULAI lapor tetep keliatan mati -> ditutup &
            -- dibuka ulang percuma.
            if (not fast) and (os.time() - stat0Ts) >= 30 then
                stat0 = api_get(cfg, "/stat")
                stat0Ts = os.time()
            end
            if (os.time() - potretTs) >= 30 then
                potretJalan = pkg_running_semua(list)
                potretTs = os.time()
            end
            -- v4.68: REM. Client yang BARU AJA dibuka-tutup jangan disentuh lagi
            -- dalam waktu dekat -- kasih dia kesempatan lapor dulu. Tanpa ini,
            -- client sehat yang laporannya telat dikit bisa kena buka-tutup
            -- berulang tiap siklus.
            local baruDisentuh = TERAKHIR_BUKA[pkg] and
                                 (os.time() - TERAKHIR_BUKA[pkg]) < (cfg.konfirmasi_sec or 90)
            -- v4.71: status dibaca dari potret gabungan (satu dumpsys buat semua),
            -- bukan dumpsys per client. Dulu 4 client = 4 panggilan su tiap
            -- open_all -- ~24 detik cuma buat mutusin "perlu disentuh nggak".
            local lagiJalan = potretJalan and potretJalan[pkg]
            if lagiJalan == nil then lagiJalan = pkg_running(pkg) end
            -- ============================================================
            -- v5.75 FIX: BEDAIN "akun gak lapor" dari "PANEL gak kejangkau".
            --
            -- bridge_fresh() balik FALSE kalau /stat gak kebaca -- dan itu
            -- kejadian buat SEMUA akun sekaligus pas panelnya gak kejangkau
            -- (kuota CF habis, jaringan putus, curl rusak).
            -- Akibatnya: gak ada satu pun client yang lolos syarat "dilewati",
            -- jadi SEMUANYA ditutup-buka. Tiap reopen_sec (300 detik).
            --
            -- Itu yang bikin "rejoin semua bareng" -- dan tiap putaran nambah
            -- satu join, sampai Roblox nolak muat data (267).
            -- Kekonfirmasi dari dua sisi: script jalan TANPA Termux gak pernah
            -- rejoin, dan kuota CF emang sempat habis berjam-jam.
            --
            -- Panel gak kejangkau itu masalah JARINGAN, bukan alasan nutup 10
            -- client. Kalau /stat gak kebaca, client dibiarin apa adanya --
            -- yang bener-bener nyangkut tetep ketangkep jalur lain (mati
            -- mendadak, auto-rejoin bridge-diem) yang gak bergantung /stat.
            -- ============================================================
            local panelBuram = (ambil_num(stat0, "skrg") == nil)
            -- v9.298: SKIP juga kalau DENYUT fresh (client idup per SD card, walau
            -- bridge/panel stale). Bug: reopen_sec re-join client hidup krn cuma
            -- ngecek bridge_fresh (panel), padahal denyut-cek udah bilang idup.
            local denyutFresh = akun and DENYUT_UMUR[akun] and DENYUT_UMUR[akun] <= 180
            if lagiJalan and (panelBuram or not akun
                              or bridge_fresh(stat0, akun) or baruDisentuh or denyutFresh) then
                hasil.lewat = hasil.lewat + 1
                -- v4.6: JANGAN print tiap client yg udah jalan (bikin spam log).
            elseif akun and KICK_DIURUS["mati:" .. akun] then
                -- v6.19: cookie akun ini MATI/BAN -> gak usah dibuka ke game.
                -- Cuma buang waktu (bakal gagal login / CREATE ACCOUNT). Skip,
                -- statusnya udah di panel (tab Error) buat diurus manual.
                hasil.lewat = hasil.lewat + 1
                info("   " .. akun .. " cookie mati -> gak dibuka (perbaiki cookie dulu)")
            elseif KICK_DIURUS["captcha:" .. pkg] then
                -- v6.65: client kena CAPTCHA -> gak dibuka (percuma, verif butuh
                -- solve manual, rejoin mancing verif lagi). Skip, badge di panel.
                hasil.lewat = hasil.lewat + 1
                info("   " .. (akun or pkg:gsub("com%.roblox%.","")) .. " KENA CAPTCHA -> gak dibuka (solve manual dulu)")
            else
                local sukses, lama, sebab = false, 0, nil
                -- v7.40: mode barengan maks 3x tembak (user minta). Kalau 3x gak
                -- masuk game -> skip client ini (ketangkep ronde berikutnya).
                -- Mode lain (lisensi habis) tetep pakai max_coba config.
                -- v8.14: paksaMasuk (lisensi baru abis bypass) = 5x tiap 30s
                -- (client HARUS masuk). start biasa = 3x. auto_key mati = cfg/5.
                local maxc = paksaMasuk and 5 or (lisensiAda and 3 or (cfg.max_coba or 5))
                urutBuka = urutBuka + 1   -- v7.39: nomor khusus yang DIBUKA
                local totalBuka = perluBuka > 0 and perluBuka or #list
                for coba = 1, maxc do
                    local link_c = mapLink and mapLink[pkg] or nil
                    setAksi(string.format("buka client %d/%d: %s%s", urutBuka, totalBuka,
                        (mapAkun and mapAkun[pkg]) or pkg:gsub("com%.roblox%.",""),
                        coba > 1 and (" (ulang "..coba.."/"..maxc..")") or ""))
                    io.write(string.format("[%d/%d] %s â€” buka%s...\n",
                        urutBuka, totalBuka, pkg, coba > 1 and (" (ulang ke-"..coba.."/"..maxc..")") or ""))
                    -- v4.17: catat ts SEBELUM buka -> nanti tunggu lapor BARU (ts naik)
                    local ts0 = (akun and not fast) and bridge_ts(api_get(cfg, "/stat"), akun) or nil
                    -- v4.58: kalau prosesnya UDAH JALAN, TUTUP DULU. 'am start' ke
                    -- Roblox yang lagi jalan itu NO-OP -- dia bakal nangkring di
                    -- server LAMA dan gak pernah pindah walau linknya udah ganti.
                    -- Sampai sini artinya client-nya emang gak lolos saringan
                    -- (bukan yang "udah jalan & lapor sehat"), jadi aman ditutup.
                    -- v7.13: MODE TEMBAK BARENGAN -- LANGSUNG tembak (open_one),
                    -- GAK tutup dulu. Grid udah ditulis SEKALI di awal (posisi
                    -- keset). User: kalau cuma tembak masuk, gak perlu tutup.
                    -- Kalau BUKAN mode ini (lisensi habis / hati2), pertahanin
                    -- perilaku lama: tutup dulu (am start ke Roblox jalan = no-op).
                    if not lisensiAda then
                        if pkg_hidup(pkg) then
                            info("   " .. pkg:gsub("com%.roblox%.","") .. " masih jalan -> ditutup dulu biar bisa pindah")
                            close_all(cfg, pkg, mapLink, true)
                            os.execute("sleep 2")
                        end
                        if petaGrid and petaGrid[pkg] then
                            local tok, tket = tata_satu(pkg, petaGrid[pkg], true)   -- v8.81: hapus lama dulu
                            if tok and tket ~= "udah pas" then
                                info("   posisi jendela " .. pkg:gsub("com%.roblox%.","") .. ": " .. tket)
                            end
                        end
                    end
                    -- v7.47: KALAU client UDAH HIDUP tapi nyangkut (grafis rendah
                    -- = di Home), 'am start' NO-OP (Android abaikan app yg udah
                    -- jalan) -> tembak gak ngefek (grafis tetep 11 MB). Fix: force-
                    -- stop client INI DULU (cuma dia, bukan semua), baru open_one
                    -- biar fresh masuk. Cuma pas hidup+nyangkut (bukan yg udah di
                    -- game). Ini gak bikin mati-bareng (cuma 1 client bermasalah).
                    -- v7.72: FORCE KILL DIBUANG (ngerusak client lain!). Balik ke
                    -- TANPA kill -- open_one pakai cmp ActivityProtocolLaunch (cara
                    -- Pandora) yang udah kebukti ISOLATED (client lain aman). Ternyata
                    -- 'am force-stop' + langsung open_one yang ganggu window clone
                    -- lain (App Cloner share window manager). ActivityProtocolLaunch
                    -- re-join tanpa kill -> cukup, gak ganggu.
                    -- v9.27: PENGAMAN GRID -- tulis grid client INI persis sebelum open_one
                    -- (kedua mode, termasuk tembak barengan). User: masih ada client ukuran
                    -- beda -> pengaman atur grid di sini. Grid ditulis 2x di awal, tapi App
                    -- Cloner kadang gak baca -> tulis ulang persis sebelum buka = fresh.
                    if petaGrid and petaGrid[pkg] then
                        local k = petaGrid[pkg]
                        local gok, gket = pcall(function() return tata_satu(pkg, k, true) end)
                        local nmp = pkg:gsub("com%.roblox%.", "")
                        if gok then
                            info(("   [grid] %s -> (%d,%d - %d,%d) %s"):format(
                                nmp, k.L, k.T, k.R, k.B,
                                (gket == "udah pas") and "udah pas" or "ketulis"))
                        else
                            warn(("   [grid] %s GAGAL: %s"):format(nmp, tostring(gket)))
                        end
                    else
                        info(("   [grid] %s -> gak dapet posisi (peta %s)"):format(
                            pkg:gsub("com%.roblox%.", ""),
                            petaGrid and "ada tapi pkg gak ada" or "KOSONG"))
                    end
                    open_one(cfg, pkg, link_c, "buka-awal")
                    TERAKHIR_BUKA[pkg] = os.time()   -- v4.68: buat rem di atas
                    -- v7.40: MODE TEMBAK BARENGAN -- tembak -> CEK GRAFIS 30s.
                    -- Kalau udah di game (grafis >= 30MB) -> SUKSES, lanjut client
                    -- berikutnya. Kalau belum (masih out/home) -> tembak LAGI,
                    -- tunggu 20s lagi. Maks 3x. Kalau 3x gak masuk -> skip client
                    -- ini (ketangkep ronde berikutnya). jaga_depan berkala (3s)
                    -- yang urus jendela, JANGAN di sini (tembak 2x).
                    if lisensiAda then
                        -- v8.43: BUANG paksaMasuk cek-grafis-30s+retry (cara lama,
                        -- lambat + banyak gagal). Setelah bypass SAMA kayak start
                        -- biasa: tembak sekali, ANGGAP sukses. Deteksi di-game
                        -- diurus loop denyut (kalau 2 menit gak denyut -> rejoin).
                        -- Gak perlu nunggu grafis per client -> cepet.
                        sukses, lama, sebab = true, 0, nil
                    else
                        -- v4.73: munculin SEMUA jendela SETELAH buka, bukan sebelum.
                        jaga_depan(cfg, mapLink)
                        local batasJalan = cfg.tunggu_sec or 45
                        sukses, lama, sebab = tunggu_jalan(pkg, batasJalan, cek_batal, cfg, link_c)
                    end
                    -- v4.59: JANGAN blokir antrean buat nungguin bridge tiap client.
                    -- Dulu tiap client bisa makan 6+ menit (nunggu proses 3x batas +
                    -- nunggu bridge 2x batas) -> 4 client = 25 menit. Sekarang:
                    -- proses nongol = cukup buat lanjut, konfirmasi bridge-nya
                    -- dilakuin SEKALIGUS di akhir buat semua client.
                    if sukses and akun and not fast then
                        tunda[#tunda+1] = { pkg = pkg, akun = akun, ts0 = ts0 }
                        break
                    elseif sukses then
                        break
                    end
                    -- v4.36b: bedain DUA jenis kegagalan, penanganannya beda:
                    --   A. bridge bilang GAK di game (nyangkut Home/age-check)
                    --      -> BUNUH client-nya, buka ulang. WAJIB dibunuh dulu:
                    --         'am start' ke app yang udah jalan itu no-op, jadi
                    --         tanpa dibunuh dia bakal nyangkut di Home selamanya.
                    --   B. gak ketauan (gak ada akun kepetakan / fast mode)
                    --      -> lanjut aja, biar client lain kebagian.
                    local nyangkut = (sebab or ""):find("nyangkut", 1, true) ~= nil
                    if lisensiAda then
                        -- v7.46: MODE TEMBAK BARENGAN -- cek_masuk_game udah nentuin
                        -- sukses (grafis >= 30MB). Kalau BELUM masuk (sukses false),
                        -- JANGAN paksa sukses cuma karena proses hidup -- itu bikin
                        -- cek grafis percuma (clienq "hidup" tapi belum di game ->
                        -- dianggap sukses). Biarin loop tembak ulang sampai grafis
                        -- naik (maks 3x). Baru di percobaan TERAKHIR nyerah (skip,
                        -- ketangkep ronde berikutnya).
                        if coba >= maxc then
                            warn(string.format("[%d/%d] %s â€” belum masuk game setelah %dx, SKIP (coba ronde berikutnya)",
                                urut, totalBuka, pkg, maxc))
                            -- sukses tetep false -> masuk hitungan gagal, tapi gak nyangkut
                            break
                        end
                        -- belum maxc -> jeda 30s + re-join (v8.11: 40s->30s, user minta)
                        -- v8.00: tiap cycle retry -> force-stop client INI dulu
                        -- v8.04: BUANG force-stop di retry (TERBUKTI biang rusak).
                        -- Analisis user: retry udah close + tunggu TAPI masih
                        -- ganggu client lain -> berarti BUKAN jeda, tapi FORCE-STOP
                        -- itu sendiri yg goyangin App Cloner service. Isolasi gacor
                        -- (v7.84) pas TANPA force-stop. Jadi retry cuma jeda 30s +
                        -- tembak ulang (open_one cara WC re-join, TANPA close).
                        warn(string.format("[%d/%d] %s â€” %s, tunggu 30s + re-join (%d/%d)...",
                            urut, totalBuka, pkg, sebab or "belum masuk", coba, maxc))
                        if lapor_fn then pcall(lapor_fn) end
                        if cek_batal and cek_batal() then break end
                        info("   " .. pkg:gsub("com%.roblox%.","") .. " tunggu 30s -> re-join murni (tanpa -S/kill)...")
                        -- jeda 30s (cek batal tiap detik biar bisa distop)
                        for _ = 1, 30 do
                            if cek_batal and cek_batal() then break end
                            os.execute("sleep 1")
                        end
                        -- v8.08: re-join MURNI (open_one cara Pandora, TANPA -S, TANPA
                        -- force-stop). -S/kill terbukti ganggu client lain. Client
                        -- nyangkut lama masuk tapi client lain PASTI aman.
                        open_one(cfg, pkg, link_c, "buka-awal")
                        TERAKHIR_BUKA[pkg] = os.time()
                    elseif nyangkut then
                        warn(string.format("[%d/%d] %s â€” nyangkut di Home; DIBUNUH terus dibuka ulang",
                            urut, #list, pkg))
                        close_all(cfg, pkg, mapLink)
                        os.execute("sleep 2")
                    elseif pkg_hidup(pkg) then
                        warn(string.format("[%d/%d] %s â€” prosesnya idup tapi gak kedeteksi di layar game; LANJUT ke client berikutnya",
                            urut, #list, pkg))
                        sukses = true   -- dihitung di blok bawah (jangan nambah di sini: dobel)
                        break
                    end
                    warn(string.format("[%d/%d] %s â€” %s (%ds), ulang...", urut, #list, pkg, sebab, lama))
                    if lapor_fn then pcall(lapor_fn) end   -- v4.33: segerin tabel tiap percobaan
                    if cek_batal and cek_batal() then break end   -- v4.16: STANDBY di tengah retry
                    if coba < maxc then
                        -- jeda naik: 5, 10, 15... biar RF sempet lega sebelum coba lagi
                        os.execute("sleep " .. (coba * 5))
                    end
                end
                if cek_batal and cek_batal() then
                    warn("STANDBY masuk -> berhenti (di tengah buka)")
                    break
                end

                if sukses then
                    hasil.ok = hasil.ok + 1
                    ok(string.format("[%d/%d] %s â€” jalan (%ds)", urut, #list, pkg, lama))
                else
                    hasil.gagal = hasil.gagal + 1
                    hasil.nama_gagal[#hasil.nama_gagal + 1] = pkg
                    err(string.format("[%d/%d] %s â€” GAGAL: %s", urut, #list, pkg, sebab or "?"))
                end

                -- lapor ke panel di sela-sela, biar gak "ilang" bermenit-menit
                if lapor_fn then pcall(lapor_fn) end

                -- napas sebelum client berikutnya (RAM sempet settle)
                if cek_batal and cek_batal() then break end   -- v4.16: STANDBY sebelum jeda
                -- v7.12: mode tembak barengan -> jeda KECIL (2s) biar cepet.
                -- Normal (lisensi habis / hati2) -> stagger penuh.
                -- v8.44: JEDA 30s antar tembak client (user minta: tiap 30s tembak
                -- 1 client, BUKAN barengan). Biar RF gak keteteran + tiap client
                -- dapet jatah resource pas masuk. Deteksi di-game via denyut (kalau
                -- 2 menit gak denyut -> rejoin), jadi gak perlu tembak barengan.
                local jedaStagger = lisensiAda and 30 or (cfg.stagger_sec or 0)
                if jedaStagger > 0 then
                    for _ = 1, jedaStagger do
                        if cek_batal and cek_batal() then break end
                        os.execute("sleep 1")
                    end
                end
            end
        end
    end
    end -- v9.133: tutup else (loop open manual cuma pas rotasi OFF)

    -- v8.13: munculin SEMUA jendela SEKALI setelah tembak bareng (start).
    -- Client belum tentu udah masuk game (gak dicek per client) -- verifikasi +
    -- tembak ulang diurus loop berkala 90s. Ini cuma nata jendela biar keliatan.
    if lisensiAda and not (cek_batal and cek_batal()) then
        pcall(function() jaga_depan(cfg, mapLink) end)
    end

    -- v7.50: KONFIRMASI BERSAMA (nunggu client lapor bareng) DIMATIIN. Gak guna
    -- lagi -- sekarang cek masuk game via GRAFIS (cek_masuk_game) langsung pas
    -- buka + loop grafis berkala. Gak perlu nunggu bridge lapor (yang bilang
    -- "belum lapor -- auto-rejoin nangani", padahal auto-rejoin udah dimatiin).
    if false and #tunda > 0 and not (cek_batal and cek_batal()) then
        local batas = cfg.konfirmasi_sec or 90
        setAksi(("nunggu %d client masuk game (bareng, %ds)"):format(#tunda, batas))
        io.write(("      nunggu %d client masuk game (bareng, maks %ds)...\n"):format(#tunda, batas))
        local mulai = os.time()
        local belum = {}
        for _, t in ipairs(tunda) do belum[t.akun] = t end
        while (os.time() - mulai) < batas do
            if cek_batal and cek_batal() then break end
            local st = api_get(cfg, "/stat")
            local sisa = 0
            for akun, t in pairs(belum) do
                local ts = bridge_ts(st, akun)
                -- v4.60: dianggap masuk kalau lapor BARU (ts naik) ATAU laporannya
                -- masih segar. Yang kedua penting: script cuma lapor tiap 120 detik
                -- kalau gak ada perubahan -- ngotot nunggu "lapor baru" bikin client
                -- yang jelas-jelas aktif tetep ditungguin lama.
                if ts and ((not t.ts0 or ts > t.ts0) or bridge_fresh(st, akun)) then
                    belum[akun] = nil            -- beneran masuk game
                else
                    sisa = sisa + 1
                end
            end
            if sisa == 0 then break end
            os.execute("sleep " .. KONFIRMASI_POLL)
        end
        local nBelum = 0
        for akun, t in pairs(belum) do
            nBelum = nBelum + 1
            warn(("%s belum lapor -- mungkin nyangkut, auto-rejoin yang nangani"):format(akun))
        end
        if nBelum == 0 then
            ok(("semua %d client kekonfirmasi masuk game"):format(#tunda))
        elseif nBelum == #tunda and #tunda >= 3 then
            -- ============================================================
            -- v5.79: `velium apk` -- unduh & pasang 10 APK client dari Node-X, buat RF baru.
--        Alur kekonfirmasi dari uji lapangan:
--          GET /  -> cookie csrfToken
--          POST /api/unlock-folder  -> HARUS bawa header X-CSRF-Token.
--            Cookie doang GAK CUKUP -- percobaan awal kena
--            "Forbidden: Invalid or missing CSRF token".
--          GET /api/folders?parentId=<id>  -> daftar + ukuran + versi di nama
--          GET /api/files/<id>/download    -> APK (~95 MB masing-masing)
--        Diunduh SATU-SATU lalu langsung dipasang & dihapus. Sepuluh APK itu
--        ~950 MB; kalau ditumpuk dulu, RF yang penyimpanannya pas-pasan penuh
--        di tengah jalan dan semuanya sia-sia.
--        Ukuran dicek sebelum pasang -- unduhan kepotong bikin `pm install`
--        gagal dengan pesan yang gak nyambung.
--        CATATAN: nama paket TERTANAM di APK-nya, jadi `pm install` naruh tiap
--        APK ke slot sendiri. Urutan unduhan GAK ngaruh ke kebenaran; nomor di
--        nama berkas cuma buat laporan.
--
-- v5.87: FIX v5.86 nembus batas 200 lokal Lua (worker mati total di baris
--        pertama). Tabel 'kandidat' diganti fungsi lokal 'coba()' yang gak
--        nambah variabel di lingkup utama. Sama akarnya kayak RRIW v5.77 --
--        file ini mepet banget ke batas, tiap lokal baru beresiko.
--
-- v5.86: FIX `velium login` "gak nemu client" padahal client lagi login akun
--        itu. Loop pencarian cuma pakai cfg.pkgs -- di RF yang config-nya
--        belum keisi, itu kosong, jadi client target (yang disebut di argumen)
--        gak pernah dicek. Sekarang client argumen masuk kandidat pertama.
--        Plus pesan dibedain: "client login akun LAIN" vs "gak ada cookie".
--
-- v5.85: `velium login` CEK cookie hidup dulu sebelum inject.
--        Endpoint users.roblox.com/v1/users/authenticated -- bedain
--        alive/dead/captcha/ban, karena tindakannya beda (captcha bisa
--        di-solve, ban nggak, dead perlu login ulang). Status disetor ke CF
--        (/cookie-status) biar panel bisa nampilin akun mana kena apa --
--        kayak Pandora yang lapor "cookie invalid" pas start.
--        Header Cookie ditulis ke berkas dulu (bukan langsung di baris
--        perintah) -- cookie 1171 char bisa nembus batas panjang argumen.
--
-- v5.84: `velium login <akun>` -- login client pakai cookie via SQL UPDATE.
--        Cara kekonfirmasi (diuji manual berkali-kali): tulis cookie ke
--        app_webview/Cookies lewat sqlite3 UPDATE (BUKAN cp -- cp bikin journal
--        SQLite gak konsisten, Roblox anggap rusak -> CREATE ACCOUNT), terus
--        buka pakai `am` (BUKAN panel -- panel nimpa cookie kita duluan).
--        Cookie diambil sekali dari client yang login akun itu, disetor ke CF,
--        seterusnya dipakai ulang.
--        uname buat nyocokin akun DI-DECODE base64 dulu (terkubur di tengah
--        cookie) -- pola teks biasa gak kena. Ketangkep pas uji.
--
-- v5.83: bilah kemajuan curl dinyalain + kecepatan dilaporin.
--        Tampilannya jadi lebih berantakan (curl nulis bilah di baris sendiri),
--        tapi ditukar sama dua hal yang lebih berguna:
--          1. keliatan angkanya JALAN. Unduhan 95 MB itu 1-3 menit, dan tanpa
--             tanda apa-apa gak ada bedanya antara "lagi jalan" sama
--             "nyangkut" -- bikin orang nunggu sia-sia atau mbatalin yang
--             sebenernya jalan.
--          2. kecepatan per client dicatet (MB/s). Bilah kemajuan lewat gitu
--             aja tanpa ninggalin jejak; angka ini yang bikin ketauan kalau
--             ada satu client yang anehnya lambat.
--        Catatan: stderr SENGAJA gak dibuang -- bilah curl ditulis ke situ,
--        kalau dibuang bilahnya ikut ilang.
--
-- v5.82: FIX unduhan APK selalu kepotong di ~10-20 MB.
--        Sebabnya sh_silent() motong tiap perintah di `timeout 8`. Buat
--        perintah biasa itu wajar -- tapi 95 MB butuh 50-100 detik.
--        Gejalanya bikin salah sangka: "GAGAL unduh (13/95 MB)" keliatan kayak
--        jaringan putus atau server nolak, padahal KITA yang motong. Ukurannya
--        beda-beda tiap kali (9, 13, 18, 21 MB) justru karena itu batas WAKTU.
--        Unduhan & `pm install` sekarang lewat os.execute/io.popen langsung
--        dengan batas sendiri (900 detik unduh, 300 detik pasang).
--        Ditambah --fail biar balasan HTTP 4xx/5xx gak kesimpen jadi berkas
--        sampah yang keliatan kayak unduhan berhasil.
--
-- v5.81: perintahnya jadi `velium download` (`dl` juga jalan).
--        `apk` DIPERTAHANIN -- RF yang udah kepasang mungkin masih pakai itu,
--        dan nambah nama lain gak ada ongkosnya sementara ngilangin yang lama
--        ada. Ikut didaftarin di `velium bantu` biar gak perlu diinget.
--
-- v5.80: `velium apk` bisa MILIH client, gak borongan.
--        Daftarnya ditampilin dulu, terus diminta pilih: "1,2,3", "1-5", atau
--        Enter buat semua.
--        Kenapa perlu: sepuluh APK itu ~950 MB dan 4-20 menit. Kalau RF cuma
--        pakai 5 client, separuhnya kepasang jadi paket yang gak pernah dibuka
--        -- makan ~475 MB penyimpanan percuma.
--        Rentang ("1-5") didukung karena itu cara nulis paling wajar buat
--        lima client pertama. Nomor di luar jangkauan ditolak satu-satu dan
--        disebutin, sisanya tetep jalan -- salah ketik satu gak bikin batal
--        semua.
--
-- v5.78: FIX deteksi masuk game NYANGKUT kalau client masuk LANGSUNG.
--        Log lapangan: "grafis clienp mendatar di 42.2 MB -- itu patokan
--        'halaman awal'". Padahal ukur `velium layar` di RF yang sama bilang
--        HOME 15 MB / GAME 49 MB -- jadi 42 MB itu udah DI DALAM GAME.
--        Cara lama cuma liat KENAIKAN, jadi dia nunggu 84 MB (2x) atau 62 MB
--        (+20MB) -- kenaikan yang UDAH LEWAT sebelum dia mulai ngukur.
--        Ditambah ambang MUTLAK 30 MB: di atas itu, langsung dianggap masuk
--        game. 30 dipilih karena persis di tengah dua nilai terukur (15/49),
--        jauh dari dua-duanya -- bukan angka bulat asal.
--        Di bawah ambang, cara kenaikan lama tetep dipakai: dia lebih peka
--        buat RF yang nilainya beda (mis. petak mungil 8 -> 22 MB).
--
-- v5.77: FIX worker MATI TOTAL di baris pertama --
--        "attempt to index a nil value (global 'RIW')".
--        `RIW.http = {...}` ada di baris ~1827, tapi `local RIW` dideklarasi
--        di ~2233. Pas dimuat, RIW masih nil.
--        Kenapa lolos pemeriksaan: penyisir urutan-deklarasi cuma nyari
--        PEMANGGILAN FUNGSI (`nama(`), gak nyari PENGAKSESAN TABEL
--        (`nama.field`). Dua-duanya masalah yang sama persis, cuma satu yang
--        dicek -- dan yang gak dicek itu justru yang lebih fatal, karena
--        jalan langsung pas berkas dimuat.
--        Penyisirnya ikut dibetulin (penyisir.py v2).
--
-- v5.76: SEMUA gagal lapor itu beda dari SEBAGIAN gagal.
            --
            -- Kalau 1-2 dari 8 gak lapor, itu masuk akal -- client-nya emang
            -- nyangkut. Tapi kalau SEMUANYA gagal, penyebab per-client gak
            -- masuk akal lagi: yang lebih mungkin ada satu hal di jalur
            -- bersama yang rusak.
            --
            -- Kejadian nyata yang bikin ini perlu: backend di-deploy pakai
            -- kolom D1 baru tapi ALTER TABLE-nya belum dijalanin. Tiap laporan
            -- ditolak D1 -> nol akun kecatat -> worker nyimpulin 8 client
            -- nyangkut -> nutup-buka semua -> join kesering -> error 267.
            -- Satu ALTER TABLE kelewat bikin seluruh armada rejoin berulang,
            -- dan gak ada satu pun pesan yang nunjuk ke sana.
            --
            -- Ini gak ngubah tindakan -- jatah bunuh tetep yang ngerem. Yang
            -- ditambahin: SEBABNYA disebut, biar gak dikira client-nya rusak.
            -- ============================================================
            warn(("SEMUA %d client gak lapor -- bukan cuma sebagian."):format(nBelum))
            warn("  Pola begini biasanya BUKAN client yang rusak.")
            warn("  Cek dulu, urut dari yang paling sering:")
            warn("   1. kolom D1 belum dibikin (ALTER TABLE kelewat)")
            warn("      -> di client, GUI script bilang 'DITOLAK: ... no column'")
            warn("   2. backend belum di-deploy / versinya ketinggalan")
            warn("   3. autoexec salah nama atau folder")
            warn("  Selama sebabnya belum kelar, nutup-buka client gak nolong.")
        end
    end

    -- v4.82: blok AUTO GRID lama (am ... resize setelah client kebuka) DICABUT.
    -- Cara itu gak pernah ngefek di ROM RedFinger -- jendelanya digambar App
    -- Cloner, bukan Android, jadi Android gak pegang posisinya. Penggantinya
    -- udah jalan di atas: koordinat ditulis ke prefs TIAP SEBELUM client dibuka.
    if petaGrid and hasil.ok > 0 then
        SUDAH_GRID = true
        catatKirim(os.date("%H:%M:%S") .. " GRID: posisi jendela ditulis buat "
                   .. hasil.ok .. " client yang baru dibuka")
    end

    -- v5.93: AUTO-SETOR COOKIE ke panel -- kayak "cookie ready" Pandora.
    -- Inline (bukan fungsi lokal -- file mepet batas 200 lokal). Tiap client
    -- jalan & login, cookie disetor sekali (penanda di KICK_DIURUS["ck:akun"]
    -- biar gak nambah lokal baru -- file mepet batas 200 lokal Lua).
    -- v6.25: scan SEMUA client Roblox kepasang (bukan cuma config) -- biar
    -- AKUN BARU yang lo bikin manual di client mana pun ke-setor otomatis ke
    -- panel. Jadi abis bikin akun, cookie-nya langsung masuk pool (bisa dipakai
    -- gantiin akun yang kena verif di RF lain). Gabung config + pindai_pkgs.
    local scanCk = {}
    do
        local ada = {}
        for _, pkg in ipairs(list) do scanCk[#scanCk+1] = pkg; ada[pkg] = true end
        for _, pkg in ipairs(pindai_pkgs()) do
            if not ada[pkg] then scanCk[#scanCk+1] = pkg end
        end
    end
    for _, pkg in ipairs(scanCk) do
        if pkg_running(pkg) then
            local db = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
            local cmd = ("su -c %s 2>/dev/null"):format(shq(
                "/data/data/com.termux/files/usr/bin/sqlite3 " .. db ..
                " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\""))
            local hC = io.popen(cmd)
            local ckC = hC and hC:read("*all") or ""
            if hC then hC:close() end
            ckC = cookie_terpanjang(ckC or "")
            -- v6.35: username DARI cookie (sinkron sama cookie), bukan prefs.xml
            -- yang bisa ketinggalan. Fallback ke mapAkun/prefs kalau decode gagal.
            local ak = (ckC ~= "" and ckC:find("_|WARNING")) and uname_dari_cookie(ckC) or nil
            if not ak or ak == "" then ak = (mapAkun and mapAkun[pkg]) or baca_username(pkg) end
            -- v6.44: PERBARUI COOKIE FRESH tiap 10 menit (bukan sekali). Cookie
            -- Roblox bisa di-rotate/refresh -- kalau cuma setor sekali, panel
            -- pegang cookie lama yang bisa mati. Perbarui berkala = panel selalu
            -- punya versi fresh dari client yang lagi login. Penanda = timestamp.
            local ckTerakhir = KICK_DIURUS["ck:" .. ak]
            local perluSetor = (type(ckTerakhir) ~= "number") or (os.time() - ckTerakhir >= 600)
            if ak and ak ~= "" and ak ~= "?" and perluSetor then
                if ckC ~= "" and ckC:find("_|WARNING") then
                    pcall(function()
                        local body = string.format('{"akun":%s,"paket":%s,"cookie":%s}',
                            jstr(ak), jstr(pkg), jstr(ckC))
                        local resp = api_post(cfg, "/cookie-simpan", body) or ""
                        if resp:find('"ok"%s*:%s*true') then
                            KICK_DIURUS["ck:" .. ak] = os.time()   -- timestamp, bukan true
                            -- v6.02: sekalian CEK HIDUP biar status gak "belum dicek".
                            -- 1 request ke Roblox per akun -- setor status juga.
                            local keadaan, ketCek = cek_cookie_roblox(ckC)
                            -- v6.17: JANGAN lapor "mati" kalau cek GAGAL (error/
                            -- timeout/koneksi) -- itu false negative, cookie bisa
                            -- aja hidup tapi cek-nya yang gagal. Cuma setor status
                            -- yang PASTI (alive/dead/captcha/ban). "error" -> skip
                            -- setor status (biarin status lama, jangan timpa "mati").
                            if keadaan == "error" then
                                info("   cookie " .. ak .. " -> panel (tersimpan, cek nanti: " ..
                                     tostring(ketCek or "cek gagal") .. ")")
                            else
                                pcall(function()
                                    api_post(cfg, "/cookie-status", string.format(
                                        '{"akun":%s,"status":%s}', jstr(ak), jstr(keadaan)))
                                end)
                                local tanda = (keadaan == "alive") and "hidup"
                                    or (keadaan == "captcha") and "captcha"
                                    or (keadaan == "ban") and "ban" or "mati"
                                -- v6.19: tandai cookie MATI/BAN biar open_all SKIP
                                -- (gak buang waktu buka client yang cookie-nya mati).
                                -- Numpang KICK_DIURUS (prefix "mati:") -- gak nambah lokal.
                                if keadaan == "dead" or keadaan == "ban" then
                                    KICK_DIURUS["mati:" .. ak] = true
                                else
                                    KICK_DIURUS["mati:" .. ak] = nil   -- hidup/captcha -> boleh buka
                                end
                                info("   cookie " .. ak .. " -> panel (" .. tanda .. ")")
                            end
                        end
                    end)
                end
            end

            -- v6.60: SEKALIAN CEK CAPTCHA di sini (pas cek cookie). Ini momen pas
            -- -- worker udah akses client ini. Cuma buat client yang HIDUP tapi
            -- cookie ALIVE (bukan mati/ban) -- karena captcha kejadian pas cookie
            -- valid tapi kena verif bot pas join. Kalau kena -> tandai + badge.
            -- v7.41: DUMP CAPTCHA pas buka DIHAPUS (uiautomator lambat). Deteksi
            -- captcha sekarang cuma pas client OFF LAMA (>= 5 menit) di jalur diem.
            -- Client yang gak lapor tapi hidup -> biarin, ketangkep jalur diem/
            -- logcat. Gak dump tiap buka (buang waktu).
        end
    end

    return hasil
end

-- ============================================================
-- notifikasi
-- ============================================================
NOTIF_ID="velium_worker"
function notify(title,content)
    local function e(s) return (s or ""):gsub('"','\\"') end
    sh_silent(string.format('termux-notification --id %s --title "%s" --content "%s" --ongoing --priority low --alert-once',
        NOTIF_ID, e(title), e(content)))
end
function notify_clear() sh_silent("termux-notification-remove "..NOTIF_ID) end

-- ============================================================
-- lapor status -> POST /tim
-- ============================================================
function baca_cpu()
    local l1 = tonumber(sh("cat /proc/loadavg"):match("^([%d%.]+)")) or 0
    local ncpu = tonumber(sh("nproc")) or 4
    local pct = math.floor(l1/ncpu*100+0.5)
    return pct > 100 and 100 or pct
end

-- v4.66: 'cache' = status client yang udah dibaca barusan. Dulu lapor()
-- manggil pkg_running SENDIRI per client -- 4 client = 4 panggilan su (~24
-- detik) TIAP LAPOR. Itu yang bikin panel telat banget update-nya, sekaligus
-- bikin satu putaran loop jadi panjang.
function lapor(cfg, isi_perintah, cache)
    local used, free, total = baca_ram()
    local list = split(cfg.pkgs)
    local parts, jalan = {}, 0
    local semua = cache
    if not semua then semua = pkg_running_semua(list) end   -- cadangan: sekali dump
    for idxPkg, pkg in ipairs(list) do
        local run = semua[pkg] and true or false
        if run then jalan = jalan + 1 end
        -- v6.03: ikut kirim NAMA AKUN tiap client biar panel bisa nunjukin
        -- "akun ini jalan di client mana".
        -- v6.41: username DARI COOKIE (akurat abis ganti akun) -- prefs.xml bisa
        -- ketinggalan. Query dikasih timeout 8s biar gak HANG kalau client beku /
        -- SQL lock. Fallback prefs.xml kalau cookie gagal/timeout.
        local akunPkg = ""
        do
            local dbC = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
            local hK = io.popen(("timeout 8 su -c %s 2>/dev/null"):format(shq(
                "/data/data/com.termux/files/usr/bin/sqlite3 " .. dbC ..
                " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
            local ckK = hK and hK:read("*all") or ""
            if hK then hK:close() end
            ckK = cookie_terpanjang(ckK or "")
            if ckK ~= "" and ckK:find("_|WARNING") then
                akunPkg = uname_dari_cookie(ckK) or ""
            end
            if akunPkg == "" then akunPkg = baca_username(pkg) or "" end
        end
        -- v6.48: ikut kirim alasan "belum ganti" (kalau ada) biar panel bisa
        -- nampilin kenapa client belum ke-ganti akun (cookie mati/ban/dll).
        local pkgPend2 = pkg:gsub("com%.roblox%.", "")
        local gg = KICK_DIURUS["gantigagal:" .. pkgPend2]
        -- v6.49: kirim "off berapa lama" (detik) biar panel nampilin durasi off.
        local offL = KICK_DIURUS["offlama:" .. pkg]
        -- v6.68 FIX: JANGAN clear captcha di sini. Dulu clear pas run=true
        -- (proses hidup), tapi client kena captcha proses-nya HIDUP tapi belum
        -- masuk game -> langsung ke-clear -> capt=false -> BADGE GAK MUNCUL.
        -- Clear captcha dipindah ke LOOP UTAMA (yang punya /stat buat bridge_fresh)
        -- -- badge ilang cuma pas client beneran udah main (solved).
        local capt = KICK_DIURUS["captcha:" .. pkg] and true or false
        -- v9.77: kirim umur denyut akun (detik). Panel pakai ini buat on/off:
        -- run=proses hidup (bisa nyangkut loading), denyut=beneran di game. Denyut
        -- >150s = akun gak lapor = OFF di panel (walau proses masih jalan).
        local denyutU = akunPkg ~= "" and DENYUT_UMUR[akunPkg] or nil
        parts[#parts+1] = string.format('{"pkg":%s,"idx":%d,"run":%s,"akun":%s,"gantigagal":%s,"offlama":%d,"captcha":%s,"denyut":%s}',
            jstr(pkg), idxPkg, tostring(run), jstr(akunPkg), jstr(gg or ""), math.floor(tonumber(offL) or 0), tostring(capt),
            denyutU and tostring(math.floor(denyutU)) or "null")
    end

    -- v4.24: ikut kirim "lagi ngapain" + log terakhir
    local logParts = {}
    for _, l in ipairs(LOG_KIRIM) do logParts[#logParts+1] = jstr(l) end

    local body = string.format(
        '{"tim":%s,"cpu":%d,"ram_used":%.1f,"ram_free":%.1f,"ram_total":%.1f,'..
        '"jalan":%d,"total":%d,"sticky":%s,"sig":%s,"clients":[%s],'..
        '"aksi":%s,"log":[%s],"ver":%s,"dev":%s,"devnama":%s,"sc":%s,'..
        '"place":%s,"grid":%d,"wnaik":%s,"wboot":%d,"wnaktif":%d,"ninstall":%d,"dslot":%s}',
        jstr(cfg.tim), baca_cpu(), used, free, total,
        jalan, #list, tostring((isi_perintah or ""):upper():find("FORCE") ~= nil),
        jstr(isi_perintah), table.concat(parts, ","),
        jstr(AKSI_SKRG), table.concat(logParts, ","), jstr(VERSION), jstr(dev_id()), jstr(devnama_now()),
        jstr(cfg.script_label or ""),
        jstr(cfg.place_id or ""), math.floor(tonumber(cfg.grid_kolom) or 0),
        WVER_NAIK and jstr(WVER_NAIK) or "null",
        BOOT_TS or 0,
        (PKGS_AKTIF and #PKGS_AKTIF > 0) and #PKGS_AKTIF or #list,
        #split(cfg.pkgs or ""),
        -- v9.104: dslot = daftar slot Delta terinstall (1..#pkgs BASE contiguous +
        -- slot yg baru didownload lewat DOWNLOAD-DELTA). Panel tandai ijo yg PERSIS.
        (function()
            local ada = {}
            for i = 1, #split(cfg.pkgs or "") do ada[i] = true end
            for n, _ in pairs(DELTA_SLOT_DL) do ada[n] = true end
            local arr = {}
            for n = 1, 30 do if ada[n] then arr[#arr+1] = n end end
            return jstr(table.concat(arr, ","))
        end)()
    )

    -- v5.30: HASIL LAPORAN DICATAT. Dulu `api_post(...)` nilai baliknya
    -- dibuang -- kalau POST /tim ditolak (kunci salah, tabel belum ada, jalur
    -- gak dikenal), worker tetep keliatan normal sementara panel KOSONG.
    -- Gagalnya diem, dan itu bikin susah dilacak.
    local resp = api_post(cfg, "/tim", body) or ""
    if resp == "" then
        LAPOR_OK, LAPOR_SEBAB = false, "gak nyambung"
    else
        local salah = ambil_str(resp, "error")
        if salah then
            LAPOR_OK, LAPOR_SEBAB = false, salah
            -- cetak sekali aja per sebab, biar log gak kebanjiran
            if LAPOR_WARN ~= salah then
                LAPOR_WARN = salah
                err("LAPOR KE PANEL DITOLAK: " .. salah)
                if salah:find("kunci") then
                    err("  -> KUNCI di config beda sama `wrangler secret put KUNCI`")
                elseif salah:find("jalur") then
                    err("  -> backend Cloudflare belum di-deploy / versinya lama")
                end
                err("  -> makanya tim ini KOSONG di panel")
            end
        else
            if not LAPOR_OK then ok("Lapor ke panel: nyambung lagi") end
            LAPOR_OK, LAPOR_SEBAB, LAPOR_WARN = true, nil, nil
            LAPOR_TS = os.time()
        end
    end
    return jalan, #list
end

-- ============================================================
-- perintah -> GET /perintah?tim=X
-- ============================================================
function is_target(w, targets)
    if not w or w == "" then return false end
    local wl = w:lower()
    for _, tgt in ipairs(split(targets)) do
        if tgt ~= "" and wl:find(tgt:lower(), 1, true) then return true end
    end
    return false
end

-- ============================================================
-- v4.1: pindai paket Roblox yang kepasang di device ini
-- Ngetik 6-10 nama paket manual itu gampang typo, dan typo-nya diem â€”
-- pgrep gak nemu, client gak kebuka, gak ada error. Mending dipindai.
-- ============================================================
-- v6.25: GLOBAL (bukan local) -- dipanggil dari open_all (lebih awal di file)
function pindai_pkgs()
    -- v9.148: timeout 20s (pm list bisa lambat di device banyak app -> kepotong
    -- 8s = sebagian roblox pkg ilang -> client 19-20 gak masuk config).
    local out = sh_tmo("su -c 'pm list packages'", 20)
    if out == "" then out = sh_tmo("pm list packages", 20) end
    local t = {}
    for baris in out:gmatch("[^\n]+") do
        local p = baris:match("^package:(%S+)")
        if p and p:lower():find("roblox", 1, true) then t[#t+1] = p end
    end
    table.sort(t, urut_alami)   -- v9.146: natural sort (folder Download order)
    return t
end

-- ============================================================
-- setup
-- ============================================================
-- PRESET DIHAPUS. Dulu `velium pasang <preset>` (farm/seed/market/gag1/...)
-- bikin config otomatis + narik script dari GitHub (ronihub). Sekarang setup
-- = wizard manual: pilih map/game doang, TANPA script. Client join game polos
-- (tulis_autoexec dilewat kalau script_url kosong). Mau script lagi? Set manual:
-- config -> script_url/script_label, atau perintah `velium script`.
-- ============================================================

function setup_wizard()
    print(C.BOLD..C.C.."\n=== VELIUM WORKER v"..VERSION.." â€” SETUP ===\n"..C.N)

    -- ============================================================
    -- v5.51: MULAI DARI CONFIG LAMA, bukan tabel kosong.
    --
    -- Dulu `local cfg = {}`. Akibatnya setiap setelan yang GAK DITANYA di
    -- wizard ini ketulis ulang jadi bawaannya -- padahal save_config nulis
    -- SEMUA field. Contoh nyatanya: auto_key.
    --   auto_key gak pernah ditanya di setup (cuma bisa diedit manual di
    --   config). Jadi tiap kali setup dijalanin ulang:
    --     tostring(cfg.auto_key == true)  ->  nil == true  ->  "false"
    --   Setelan true yang udah diisi manual KEHAPUS DIAM-DIAM, dan gejalanya
    --   cuma "auto_key MATI" di log -- keliatan kayak user gak pernah nyetel.
    -- Field lain yang senasib: delta_license, key_jam, autoexec_bersih,
    -- suplai_master, script_label, dan setelan apa pun yang ditambah nanti.
    -- ============================================================
    local cfg = {}
    do
        local lama = load_config()
        if lama then
            cfg = lama
            ok("Setelan lama dibaca dari " .. CONFIG_FILE)
            local jaga = {}
            if cfg.auto_key == true then jaga[#jaga+1] = "auto_key=true" end
            if (cfg.bypass_api_key or "") ~= "" then jaga[#jaga+1] = "kunci API" end
            if cfg.key_jam and cfg.key_jam ~= 24 then jaga[#jaga+1] = "key_jam=" .. cfg.key_jam end
            if cfg.autoexec_bersih == false then jaga[#jaga+1] = "autoexec_bersih=false" end
            if #jaga > 0 then
                info("  yang gak ditanya di bawah TETEP kepakai: " .. table.concat(jaga, ", "))
            end
        end
    end

    -- URL + KUNCI DIKUNCI (hardcoded). User GAK BISA ubah -- biar gak ada
    -- salah ketik yang bikin worker nyasar ke backend lain / kunci salah.
    cfg.url = "https://velium-worker.edchen114.workers.dev"
    cfg.kunci = "9f4c2a8e-7d1b-4f6c-9e3a-2b5d8f1a6c7e"
    info("Panel : " .. cfg.url)

    print("")
    print(C.D.."  1 tim = 1 RedFinger. Nama HARUS sama kayak TIM di star_bridge.lua."..C.N)
    -- Isi ANGKA doang, prefiks "tim-" ditempel otomatis -- sama persis kayak
    -- kolom Tim di star_farm.lua. Prefiks yang beda ("tim1"/"Tim-1") bikin akun
    -- gak nempel ke tim ini dan panel keliatan kosong TANPA error apa pun.
    local DEV = dev_id()

    -- v5.51: BAWAANNYA DARI CONFIG LAMA, bukan "1" mati.
    -- Dulu bawaannya selalu "1". Di RF yang udah jalan sebagai tim-4, tekan
    -- Enter di sini = pindah ke tim-1 DIAM-DIAM. Akibatnya berat: akun kepindah
    -- tim, perintah panel nyasar, dan gak ada yang ngasih tau.
    -- Sekarang bawaannya nomor yang sekarang, dan kalau diubah -> dikonfirmasi.
    local timLama = tostring(cfg.tim or ""):match("tim%-(%d+)")
    if timLama then
        info("Tim RF ini sekarang: tim-" .. timLama .. "  (Enter = biarin)")
    end
    local tn
    while true do
        tn = tonumber((ask("Nomor tim (angka aja)", timLama or "1") or ""):match("%d+") or "")
        if not tn or tn < 1 then
            warn("Isi angka, minimal 1.")
        elseif timLama and tostring(tn) ~= timLama then
            -- ganti tim itu tindakan besar -- jangan kejadian gara-gara salah ketik
            warn("Tim RF ini sekarang tim-" .. timLama .. ", mau diganti ke tim-" .. tn .. "?")
            warn("  Akibatnya: akun di RF ini pindah ke tim-" .. tn .. ", dan perintah")
            warn("  buat tim-" .. timLama .. " gak nyampe lagi ke sini.")
            local ya = ask("Yakin ganti? (y/n)", "n")
            if ya:lower() == "y" then
                local calon = "tim-" .. tn
                cfg.tim = calon
                local r = api_get(cfg, "/tim-klaim?tim=" .. calon .. "&dev=" .. DEV)
                local boleh = ambil_str(r, "boleh")
                if boleh == nil then
                    warn("Gak bisa ngecek ke server (URL/kunci bener? internet nyala?)")
                    warn("Lanjut pakai " .. calon .. " -- pastiin sendiri gak dipake RF lain.")
                    break
                elseif boleh == "ya" then
                    break
                else
                    local sebab = ambil_str(r, "sebab") or (calon .. " udah dipegang device lain")
                    warn("DITOLAK: " .. sebab)
                end
            else
                info("Dibatalin -- tetep tim-" .. timLama)
                tn = tonumber(timLama)
                cfg.tim = "tim-" .. tn
                break
            end
        else
            local calon = "tim-" .. tn
            cfg.tim = calon
            local r = api_get(cfg, "/tim-klaim?tim=" .. calon .. "&dev=" .. DEV)
            local boleh = ambil_str(r, "boleh")
            if boleh == nil then
                -- server gak kejawab (URL/kunci salah, atau lagi offline).
                -- jangan ngunci setup: kasih tau, terus terusin.
                warn("Gak bisa ngecek ke server (URL/kunci bener? internet nyala?)")
                warn("Lanjut pakai " .. calon .. " -- pastiin sendiri gak dipake RF lain.")
                break
            elseif boleh == "ya" then
                break
            else
                local sebab = ambil_str(r, "sebab") or (calon .. " udah dipegang device lain")
                warn("DITOLAK: " .. sebab)
                local dipakai = r and r:match('"terpakai"%s*:%s*%[(.-)%]') or ""
                dipakai = dipakai:gsub('"', ''):gsub("tim%-", "")
                if dipakai ~= "" then
                    info("Nomor yang udah kepake: " .. dipakai)
                end
                info("Pilih nomor lain.")
            end
        end
    end
    cfg.tim = "tim-" .. tn
    ok("Tim: " .. cfg.tim)
    -- pasang klaim: mulai sekarang RF lain gak bisa ambil nomor ini
    local rk = api_post(cfg, "/tim-klaim", string.format('{"tim":%s,"dev":%s}',
        jstr(cfg.tim), jstr(DEV)))
    if ambil_str(rk, "boleh") == "ya" then ok("Nomor tim ini kekunci buat RF ini") end
    -- v4.5: pemicu di-hardcode FORCE (cuma itu yg dikirim panel). gak usah nanya.
    cfg.targets="FORCE"
    -- v4.5: pilih game -> otomatis isi Place ID (gak usah ketik manual)
    print(C.D.."  Pilih game buat tim ini:"..C.N)
    print(C.D.."    1) GAG 2  (farm/garden)      -> 129343810645058"..C.N)
    print(C.D.."    2) GAG 1  (garden)           -> 126884695634066"..C.N)
    print(C.D.."    3) GAG 1 MARKET (TradeWorld) -> 129954712878723"..C.N)
    -- v5.51: bawaan ikut game yang SEKARANG, bukan "1" mati. Masalahnya sama
    -- kayak nomor tim: di RF GAG 1, tekan Enter di sini bikin dia jadi GAG 2
    -- diam-diam -- place_id ganti, client join ke game yang salah.
    local pilLama = ({ ["GAG 2"] = "1", ["GAG 1"] = "2", ["GAG 1 MARKET"] = "3" })[cfg.game_label or ""]
    if pilLama then
        info("Game RF ini sekarang: " .. cfg.game_label .. "  (Enter = biarin)")
    end
    local pil = ask("Pilih (1/2/3)", pilLama or "1")
    if pil == "2" then
        cfg.place_id = "126884695634066"; cfg.game_label = "GAG 1"
    elseif pil == "3" then
        cfg.place_id = "129954712878723"; cfg.game_label = "GAG 1 MARKET"
    else
        cfg.place_id = "129343810645058"; cfg.game_label = "GAG 2"
    end
    print(C.G.."  -> "..cfg.game_label.." (place "..cfg.place_id..")"..C.N)

    -- ============================================================
    -- SCRIPT DIHAPUS. Dulu wizard nanya STAR FARM / STAR SEED / MARKET terus
    -- narik script dari GitHub (ronihub) via autoexec. Sekarang: TANPA script.
    -- Client join game polos. tulis_autoexec dilewat kalau script_url kosong.
    -- Mau script lagi? Set manual di config (script_url/script_label) atau
    -- perintah `velium script`.
    -- ============================================================
    cfg.script_url = ""
    cfg.script_label = ""
    print(C.D.."  Link join: paste share-URL ATAU linkCode. kosong=public."..C.N)
    cfg.link_code=ask("Link/code (Enter=public)","")
    -- v5.36: pertanyaan "Folder autoexec" DIBUANG. Jawabannya selalu sama --
    -- 20 RF = 20 kali mencet Enter buat nilai yang gak pernah beda. Nilainya
    -- tetep ada di config (ada cadangan juga di run() & tulis_autoexec), jadi
    -- kalau suatu saat ada RF yang foldernya beda, tinggal edit config-nya:
    --   autoexec_dir="/path/lain"
    cfg.autoexec_dir = cfg.autoexec_dir or "/sdcard/Delta/Autoexecute"

    -- ===== paket: dipindai, bukan diketik =====
    print()
    info("Mindai paket Roblox di device ini...")
    local ada = pindai_pkgs()
    if #ada == 0 then
        warn("Gak nemu paket Roblox. Root jalan? Client kepasang?")
        cfg.pkgs = ask("Paket Roblox (ketik manual, pisah koma)","com.roblox.client")
    else
        ok("Ketemu "..#ada.." client:")
        print("")
        for i, p in ipairs(ada) do
            local jalan = pkg_running(p) and " [jalan]" or ""
            -- tanpa warna ANSI biar gak ke-wrap berantakan di layar RF sempit
            print("   " .. i .. ". " .. p .. jalan)
        end
        print("")
        print("  Enter = pakai SEMUA")
        print("  atau ketik nomor pisah koma, misal: 1,3,5")
        print("")
        local j = ask("Pakai yang mana","")

        if j == "" or j:lower() == "semua" then
            cfg.pkgs = table.concat(ada, ",")
        elseif j:find("com%.") then
            cfg.pkgs = j
        else
            local pilih = {}
            for n in j:gmatch("%d+") do
                local p = ada[tonumber(n)]
                if p then pilih[#pilih+1] = p end
            end
            if #pilih == 0 then
                warn("Gak ada nomor yang cocok -> pakai semua")
                cfg.pkgs = table.concat(ada, ",")
            else
                cfg.pkgs = table.concat(pilih, ",")
            end
        end
    end

    cfg.poll_sec=tonumber(ask("Cek perintah tiap brp detik","5")) or 5
    print(C.D.."  Jeda minimal antar buka Roblox (biar gak spam)."..C.N)
    cfg.reopen_sec=tonumber(ask("Jeda cek-ulang client (detik)","300")) or 300
    local ar = ask("Auto-rejoin kalau akun keluar game? (y/n)","y")
    cfg.auto_rejoin = (ar:lower() ~= "n")
    cfg.auto_rejoin_menit = tonumber(ask("Auto-rejoin kalau script off berapa menit","8")) or 8
    print(C.D.."  Nunggu berapa lama sampai 1 client dianggap gagal."..C.N)
    print(C.D.."  Roblox di RedFinger biasanya 10-30 detik sampai proses muncul."..C.N)
    cfg.tunggu_sec=tonumber(ask("Batas tunggu per client (detik)","60")) or 60
    print(C.D.."  Nunggu bridge konfirmasi BENERAN masuk game (bukan nyangkut Home)."..C.N)
    print(C.D.."  Script lapor tiap ~20 detik; kasih ruang loading + verif. 90 aman."..C.N)
    cfg.konfirmasi_sec=tonumber(ask("Batas konfirmasi masuk game (detik)","90")) or 90
    print(C.D.."  Kalau gagal, diulang berapa kali sebelum nyerah."..C.N)
    cfg.max_coba=tonumber(ask("Coba ulang max per client","5")) or 5
    print(C.D.."  Napas setelah 1 client jalan, sebelum buka berikutnya."..C.N)
    cfg.stagger_sec=tonumber(ask("Jeda antar client (detik)","15")) or 15
    print(C.D.."  Tiap brp detik lapor CPU/RAM ke panel."..C.N)
    cfg.status_sec=tonumber(ask("Kirim status tiap (detik)","20")) or 20
    print(C.D.."  Mode jendela. Kalau client lo udah auto-freeform, biarin 0."..C.N)
    print(C.D.."    0 = jangan disenggol (bawaan)  |  5 = paksa freeform"..C.N)
    cfg.win_mode=tonumber(ask("Mode jendela","0")) or 0
    -- v5.37: pertanyaan shell root tetap DIBUANG, dan bawaannya jadi NYALA.
    -- Dulu ditanya dengan bawaan "n" -- padahal ini selalu dijawab y, dan
    -- untungnya besar: tiap 'su' di RedFinger makan ~6 detik, ini bikin izin
    -- root dibuka SEKALI aja.
    -- Aman dipaksa nyala karena cadangannya lengkap: dites pas nyala (gagal =
    -- balik ke cara lama), dan kalau shell-nya mati di tengah jalan kedeteksi
    -- juga. Jadi paling jelek dia cuma balik ke perilaku lama.
    -- Mau matiin di RF tertentu? edit config -> shell_tetap=false
    if cfg.shell_tetap == nil then cfg.shell_tetap = true end

    print(C.D.."  Delta Lite suka nguncup jadi gelembung sendiri. Kalau dibiarin,"..C.N)
    print(C.D.."  Roblox di dalemnya disconnect ~15 detik kemudian. Worker bisa"..C.N)
    print(C.D.."  munculin ulang jendelanya berkala. Isi 0 = mati, 10 = tiap 10 detik."..C.N)
    cfg.jaga_depan_sec = tonumber(ask("Jaga jendela tetep nongol tiap (detik)","10")) or 10  -- v5.91: fallback 10, bukan 0 (0 = mati)

    -- v5.38: pertanyaan "Auto grid?" DIBUANG, bawaannya NYALA.
    -- Grid itu bukan pilihan gaya -- jendela HARUS ketata biar URL key Delta
    -- bisa diambil dari tiap client. Jadi nanya y/n itu gak masuk akal.
    -- Susunannya juga udah otomatis: grid_hitung baca ukuran layar sendiri dan
    -- ngitung dari jumlah client (4 client -> 2x2, lihat tabel SUSUNAN).
    -- Mau matiin di RF tertentu? edit config -> auto_grid=false
    if cfg.auto_grid == nil then cfg.auto_grid = true end
    do
        local n = #split(cfg.pkgs or "")
        local sus = SUSUNAN[n]
        if sus then
            info(("Auto grid nyala -- %d client -> %dx%d (otomatis dari jumlah client)")
                :format(n, sus[1], sus[2]))
        elseif n > 0 then
            info(("Auto grid nyala -- %d client, susunan dihitung dari ukuran layar")
                :format(n))
        else
            info("Auto grid nyala")
        end
    end
    print(C.D.."  Kunci orientasi layar RF. Kosongin kalau gak mau disenggol."..C.N)
    print(C.D.."    landscape / portrait / (Enter = jangan disenggol)"..C.N)
    local ori = ask("Orientasi layar",""):lower()
    cfg.orientasi = (ori == "landscape" or ori == "portrait") and ori or ""
    print(C.D.."  Keep-alive: bikin client tahan di background (anti force-close)."..C.N)
    print(C.D.."  Di RAM sesek ini NGURANGIN kill, bukan ngilangin. Worker tetep aman."..C.N)
    local ka = ask("Keep-alive (anti-FC)? (y/n)","y")
    cfg.keep_alive = (ka:lower() ~= "n")

    -- v5.51: auto_key SEKARANG DITANYA. Dulu cuma bisa diedit manual di config
    -- -- dan itu yang bikin masalah: gak keliatan di setup, jadi user gak tau
    -- dia ada, dan tiap setup ulang nilainya kehapus tanpa suara.
    print("")
    print(C.D.."  Bypass key Delta otomatis: kalau lisensi hilang, worker cari"..C.N)
    print(C.D.."  key-nya sendiri (buka 1 client, ambil link, tembak API)."..C.N)
    print(C.D.."  Butuh kunci API bypass.vip -- udah ketanam di worker."..C.N)
    local akd = (cfg.auto_key == true) and "y" or "y"   -- bawaan y
    local ak2 = ask("Bypass key otomatis? (y/n)", akd)
    cfg.auto_key = (ak2:lower() ~= "n")

    -- v5.31: GAK DITANYA LAGI. Kuncinya diisi SEKALI di panel, semua RF
    -- narik dari sana. Dulu ditanyain tiap setup -- 20 RF = 20 kali ngetik
    -- kunci yang sama, dan sekali salah ketik `velium key` gagal tanpa sebab
    -- yang jelas. Kalau RF ini butuh kunci BEDA (jarang), isi manual:
    --   velium key set <APIKEY>
    cfg.bypass_api_key = cfg.bypass_api_key or ""
    if cfg.bypass_api_key ~= "" then
        info("Kunci API bypass: pakai yang udah ada di config RF ini.")
    else
        info("Kunci API bypass: diambil dari panel (isi sekali di tab Seed).")
        info("  Kalau RF ini perlu kunci sendiri: velium key set <APIKEY>")
    end

    local n = #split(cfg.pkgs)
    save_config(cfg)
    ok("Config disimpan: "..CONFIG_FILE)

    -- ============================================================
    -- v6.87: PERINTAH AWAL = STANDBY (bukan FORCE lagi). User minta FORCE HARUS
    -- dari panel -- RF baru selesai setup itu STANDBY dulu (cek cookie/lisensi,
    -- GAK buka client), nunggu user pencet "Jalankan semua" di panel. Dulu
    -- (v5.39) setup langsung FORCE -> client kebuka sendiri pas pasang, padahal
    -- user mau kontrol kapan start dari panel.
    do
        local r = api_post(cfg, "/perintah",
            string.format('{"tim":%s,"isi":"STANDBY"}', jstr(cfg.tim)), "PUT")
        local salah = ambil_str(r or "", "error")
        if r == "" then
            warn("Perintah awal gak kekirim (panel gak nyambung).")
        elseif salah then
            warn("Perintah awal ditolak panel: " .. salah)
        else
            ok("Perintah awal: STANDBY -- client GAK dibuka dulu.")
            info("  Pencet 'Jalankan semua' di panel buat mulai.")
        end
    end

    -- v5.22: pasang.sh nanya kunci API SEBELUM config ada, jadi dia nyimpen
    -- sementara. Sekarang config-nya udah kebentuk -- pasang kuncinya, terus
    -- berkas sementaranya dihapus (biar kunci gak nyangkut di dua tempat).
    do
        local jalur = (os.getenv("HOME") or ".") .. "/.velium_apikey_sementara"
        local f = io.open(jalur, "r")
        if f then
            local k = (f:read("*l") or ""):gsub("%s+", "")
            f:close()
            if k ~= "" then
                local sukses, sebab = config_set_bypass(k)
                if sukses then ok("Kunci API bypass.vip dipasang dari pasang.sh")
                else warn("Gagal masang kunci API: " .. tostring(sebab)) end
            end
            os.remove(jalur)
        end
    end
    info("Tim '"..cfg.tim.."' pegang "..n.." client:")
    for _, p in ipairs(split(cfg.pkgs)) do print(C.D.."   - "..p..C.N) end
    if n == 1 then warn("Baru 1 paket. Yakin? Biasanya 1 tim isinya 6-10.") end
    return cfg
end

-- ============================================================
-- jalan
-- ============================================================
-- v9.01: verifikasi false-alarm lisensi (GLOBAL, hemat lokal run). Return true
-- kalau lisensi "hilang" ternyata FALSE ALARM (masih ada). Cek: (1) baca ulang
-- lisensi (jeda 3s), (2) denyut fresh (client di game = key pasti ada).
function lisensi_false_alarm(cfg)
    os.execute("sleep 3")
    if lisensi_keadaan(cfg) == "ada" then return true end
    local now2 = os.time()
    local raw = sh("su -c 'cd \"" .. cfg.workspace_dir .. "\" 2>/dev/null && for f in velium_denyut_*.txt; do [ -f \"$f\" ] && echo \"$(stat -c %Y \"$f\" 2>/dev/null)\"; done' 2>/dev/null") or ""
    for tsStr in raw:gmatch("(%d+)") do
        local ts = tonumber(tsStr)
        if ts and (now2 - ts) <= 90 then return true end   -- denyut fresh = di game = key ada
    end
    return false
end

-- v9.01: RESTART logic (dipindah ke GLOBAL biar lokal gak masuk hitungan run(cfg)
-- batas 200). Tutup semua client -> buka fresh dari nol dengan setting baru.
-- Return: daftar PKGS_AKTIF (client yg dibuka) buat grid, atau nil (semua).
function restart_kerjakan(cfg, isi, mapAkun, mapLink, ada_stop)
    warn("RESTART dari panel -> tutup SEMUA client, mulai dari nol")
    -- v9.87: cek batal pas buka client = ada_perintah_baru (bukan cuma ada_stop).
    -- Biar UPDATE/REBOOT/STOP dari panel MOTONG buka-client di tengah (kayak FORCE).
    -- RESTART/FORCE yg lagi jalan gak self-interrupt (ada_perintah_baru cek isi).
    local function batal_buka() return ada_perintah_baru(cfg, isi) end
    local n = close_all_cepat(cfg)   -- tutup barengan (cepet)
    ok("RESTART: " .. n .. " client ditutup -- buka ulang fresh...")
    os.execute("sleep 3")   -- proses bener2 mati (App Cloner baca prefs pas mati total)
    -- v9.24: place udah keset dari denyut-loop (PLACE diproses di awal denyut,
    -- sebelum RESTART). Gak perlu nunggu lagi -- dulu (v9.20) nunggu PLACE di
    -- perintah DB, TAPI RESTART udah NIMPA PLACE di situ (1 slot) -> gak pernah
    -- dapet -> nyangkut "minta terus". Sekarang langsung pakai cfg.place_id yg
    -- udah keset. Kalau W2 FALL, PS link udah diambil (auto getps di denyut).
    info("Place kepakai: " .. tostring(cfg.place_id) .. " (udah keset dari denyut)")
    -- v9.22: set PKGS_AKTIF dari daftar DULU (sebelum cek/atur grid) biar pakai
    -- jumlah client yg bener. RESTART:daftar -> client tertentu. RESTART polos ->
    -- nil (semua client).
    do
        local dR = isi:match("RESTART:([%w%.%_%-,]+)")
        if dR then
            local onlyR = {}
            for a in dR:gmatch("[^,]+") do onlyR[a] = true end
            local pkgsR = {}
            for _, pkg in ipairs(split(cfg.pkgs)) do
                local u = (mapAkun or {})[pkg]
                local nm = pkg:gsub("com%.roblox%.", "")
                if onlyR[u] or onlyR[pkg] or onlyR[nm] then pkgsR[#pkgsR+1] = pkg end
            end
            PKGS_AKTIF = (#pkgsR > 0) and pkgsR or nil
            -- v9.77: log biar keliatan RESTART:daftar ke-match berapa client.
            -- Kalau 0 match -> PKGS_AKTIF nil -> BUKA SEMUA (bug "pilih 6 jalan 10").
            local nDiminta = 0; for _ in pairs(onlyR) do nDiminta = nDiminta + 1 end
            info(("[restart-daftar] diminta %d client -> ke-match %d dari %d total%s"):format(
                nDiminta, #pkgsR, #split(cfg.pkgs),
                (#pkgsR == 0) and " !! 0 MATCH -> BUKA SEMUA (cek nama akun di daftar)" or ""))
        else
            PKGS_AKTIF = nil
        end
        -- v9.90: JANGAN PERNAH buka SEMUA. Kalau PKGS_AKTIF nil (RESTART polos /
        -- 0 match) -> pakai client yg ADA AKUN sebagai daftar. Harus selalu ada
        -- daftar dulu, gak pernah polos (buka 10 termasuk clone kosong).
        if (not PKGS_AKTIF or #PKGS_AKTIF == 0) and mapAkun then
            local pk = {}
            for _, pkg in ipairs(split(cfg.pkgs)) do
                local u = mapAkun[pkg]
                if u and tostring(u) ~= "" then pk[#pk+1] = pkg end
            end
            if #pk > 0 then
                PKGS_AKTIF = pk
                info(("[restart-daftar] polos/0-match -> pakai %d client yg ADA AKUN (gak buka semua)"):format(#pk))
            end
        end
    end
    -- v9.117: ROTASI -> buka CUMA tim 1 (1-10). Panel kirim semua 20 (biar tim 2
    -- tetep kecentang di UI), tapi worker batesin ke tim 1. Tim 2 (11-20) standby,
    -- baru kebuka pas rotasi trigger (buka_grup_rotasi).
    if cfg.rotasi_on and PKGS_AKTIF and #PKGS_AKTIF > 0 then
        local list = split(cfg.pkgs)
        local set1 = {}
        for i = 1, math.min(TIM1_AKHIR, #list) do set1[list[i]] = true end
        local tim1 = {}
        for _, pkg in ipairs(PKGS_AKTIF) do if set1[pkg] then tim1[#tim1+1] = pkg end end
        if #tim1 > 0 then
            PKGS_AKTIF = tim1
            info(("[rotasi] rotasi_on -> buka cuma TIM 1 (%d client), tim 2 standby"):format(#tim1))
        end
    end
    -- bener (kolom sesuai target), GAK PERLU hapus + tulis ulang -- langsung open.
    -- Baca prefs semua client vs target; kalau SEMUA pas (toleransi 3px) -> skip
    -- bersihin + ronde tulis grid (hemat waktu banyak). SUDAH_GRID tetep true.
    local gridUdahPas = false
    do
        local pkgsCek = PKGS_AKTIF or split(cfg.pkgs)
        local petaCek = grid_hitung(cfg, pkgsCek)
        if petaCek then
            local semua, pas = 0, 0
            for _, pkg in ipairs(pkgsCek) do
                if petaCek[pkg] then
                    semua = semua + 1
                    local path = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
                    local isiP = sh("su -c 'cat " .. path .. " 2>/dev/null'") or ""
                    local L = tonumber(isiP:match('<int name="app_cloner_current_window_left" value="(%-?%d+)"'))
                    local T = tonumber(isiP:match('<int name="app_cloner_current_window_top" value="(%-?%d+)"'))
                    local R = tonumber(isiP:match('<int name="app_cloner_current_window_right" value="(%-?%d+)"'))
                    local B = tonumber(isiP:match('<int name="app_cloner_current_window_bottom" value="(%-?%d+)"'))
                    local t = petaCek[pkg]
                    if L and T and R and B
                       and math.abs(L - t.L) <= 3 and math.abs(T - t.T) <= 3
                       and math.abs(R - t.R) <= 3 and math.abs(B - t.B) <= 3 then
                        pas = pas + 1
                    end
                end
            end
            if semua > 0 and pas == semua then
                gridUdahPas = true
                info(("[cek-grid] %d/%d client grid UDAH PAS (%s kolom) -- skip hapus+tulis, langsung open"):format(
                    pas, semua, (tonumber(cfg.grid_kolom) or 0) > 0 and tostring(cfg.grid_kolom) or "auto"))
                SUDAH_GRID = true   -- grid udah bener -> open_all gak perlu tulis lagi
            else
                info(("[cek-grid] %d/%d client grid pas -- ada yg meleset, atur ulang"):format(pas, semua))
            end
        end
    end
    if not gridUdahPas then
    -- v9.17: HAPUS posisi grid LAMA semua client DULU (client udah mati, prefs
    -- aman ditimpa) -> gak ada sisa kolom lama nyangkut pas grid baru ditulis.
    pcall(function() bersihin_grid_semua(cfg) end)
    -- v9.21: reset SUDAH_GRID + cache SETELAH bersihin. Bug user: grid kehapus
    -- (bersihin) TAPI SUDAH_GRID masih true -> open_all SKIP tulis -> fullscreen.
    SUDAH_GRID = false
    GRID_CACHE = nil
    -- keset (App Cloner belum baca prefs / timing). Tulis grid ke semua client
    -- 2x (ronde 1 -> jeda 10s -> ronde 2) biar bener2 kepasang sebelum client
    -- dibuka. Pakai grid_hitung (grid_kolom=5 dari panel) -> peta posisi.
    do
        -- v9.29: grid dihitung dari JUMLAH CLIENT DIMINTA (PKGS_AKTIF kalau ada,
        -- atau SEMUA cfg.pkgs). 2 PENGAMAN: (1) jumlah client dari yg diminta,
        -- (2) client BARU (prefs belum ada) dibuka bentar dulu biar prefs kebentuk,
        -- baru grid ditulis. Bug user: client baru prefs belum ada -> tata_satu
        -- gagal -> "6 ketulis" (bukan 10) -> 4 client fullscreen.
        local pkgsBuatGrid = PKGS_AKTIF or split(cfg.pkgs)
        -- cek client yg prefs-nya BELUM ADA (client baru) -> buka bentar dulu
        do
            local perluBuka = {}
            for _, pkg in ipairs(pkgsBuatGrid) do
                local path = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
                local ada = sh("su -c 'test -f " .. path .. " && echo ADA'") or ""
                if not ada:find("ADA") then perluBuka[#perluBuka+1] = pkg end
            end
            if #perluBuka > 0 then
                info(("%d client baru (prefs belum ada) -> buka bentar biar prefs kebentuk..."):format(#perluBuka))
                for _, pkg in ipairs(perluBuka) do
                    sh_silent("su -c 'monkey -p " .. pkg .. " -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1'")
                    os.execute("sleep 2")
                    sh_silent("su -c 'am force-stop " .. pkg .. "'")
                    info("   " .. pkg:gsub("com%.roblox%.", "") .. " dibuka+tutup (prefs kebentuk)")
                end
                os.execute("sleep 2")
            end
        end
        local petaG = grid_hitung(cfg, pkgsBuatGrid)
        if petaG then
            -- v9.132: ronde 1+2 wajib, terus CEK posisi aktual. Kalau masih ada yg
            -- meleset -> ronde lagi (sampai semua pas / max 5 ronde). Biar grid bener
            -- bener rapi sebelum open.
            local MAX_RONDE = 5
            for ronde = 1, MAX_RONDE do
                info(("Atur grid ronde %d (%d client diminta, sebelum open)..."):format(ronde, #pkgsBuatGrid))
                local nOk, nGagal = 0, 0
                for _, pkg in ipairs(pkgsBuatGrid) do
                    if petaG[pkg] then
                        local gok, gket = pcall(function() return tata_satu(pkg, petaG[pkg], true) end)
                        if gok then nOk = nOk + 1
                        else
                            nGagal = nGagal + 1
                            if ronde >= 2 then warn("   grid " .. pkg:gsub("com%.roblox%.", "") .. " GAGAL: " .. tostring(gket)) end
                        end
                    end
                end
                info(("  ronde %d: %d client grid ketulis%s"):format(
                    ronde, nOk, nGagal > 0 and (", " .. nGagal .. " GAGAL") or ""))
                -- ronde 1: jeda 10s lanjut ronde 2 (gak cek dulu)
                if ronde == 1 then
                    info("Grid ronde 1 kelar -- jeda 10s sebelum ronde 2...")
                    os.execute("sleep 10")
                else
                    -- v9.132: ronde >=2 -> CEK posisi aktual vs target. Pas semua -> stop.
                    os.execute("sleep 2")   -- kasih waktu prefs ke-flush sebelum baca
                    local pasN, semuaN = 0, 0
                    for _, pkg in ipairs(pkgsBuatGrid) do
                        local t = petaG[pkg]
                        if t then
                            semuaN = semuaN + 1
                            local path = "/data/data/" .. pkg .. "/shared_prefs/" .. pkg .. "_preferences.xml"
                            local isiP = sh("su -c 'cat " .. path .. " 2>/dev/null'") or ""
                            local L = tonumber(isiP:match('<int name="app_cloner_current_window_left" value="(%-?%d+)"'))
                            local T = tonumber(isiP:match('<int name="app_cloner_current_window_top" value="(%-?%d+)"'))
                            local R = tonumber(isiP:match('<int name="app_cloner_current_window_right" value="(%-?%d+)"'))
                            local B = tonumber(isiP:match('<int name="app_cloner_current_window_bottom" value="(%-?%d+)"'))
                            if L and T and R and B
                               and math.abs(L - t.L) <= 3 and math.abs(T - t.T) <= 3
                               and math.abs(R - t.R) <= 3 and math.abs(B - t.B) <= 3 then
                                pasN = pasN + 1
                            end
                        end
                    end
                    info(("  [cek-grid ronde %d] %d/%d client grid pas"):format(ronde, pasN, semuaN))
                    if semuaN > 0 and pasN == semuaN then
                        ok(("Grid RAPI semua (%d/%d) setelah %d ronde -- lanjut open"):format(pasN, semuaN, ronde))
                        break
                    elseif ronde < MAX_RONDE then
                        warn(("  masih %d meleset -> atur grid ronde lagi..."):format(semuaN - pasN))
                        os.execute("sleep 3")
                    else
                        warn(("  %d client grid tetep meleset setelah %d ronde -- lanjut open apa adanya"):format(semuaN - pasN, MAX_RONDE))
                    end
                end
            end
        else
            warn("Grid gagal dihitung (peta nil) -- open client tanpa pre-grid")
        end
    end
    end -- v9.73: tutup 'if not gridUdahPas' (skip bersihin+tulis kalau grid udah pas)
    local daftarR = isi:match("RESTART:([%w%.%_,]+)")
    if daftarR then
        local onlyR = {}
        for a in daftarR:gmatch("[^,]+") do onlyR[a] = true end
        local pkgsR = {}
        for _, pkg in ipairs(split(cfg.pkgs)) do   -- v9.15: urutan config (bukan pairs acak)
            local u = (mapAkun or {})[pkg]
            local nm = pkg:gsub("com%.roblox%.", "")
            if onlyR[u] or onlyR[pkg] or onlyR[nm] then pkgsR[#pkgsR+1] = pkg end
        end
        if #pkgsR > 0 then
            open_all(cfg, pkgsR, batal_buka, nil, mapLink, mapAkun, false, true)
            notify("Velium "..cfg.tim, "RESTART -> buka ulang fresh")
            return pkgsR
        end
    end
    open_all(cfg, nil, batal_buka, nil, mapLink, mapAkun, false, true)
    notify("Velium "..cfg.tim, "RESTART -> buka ulang fresh")
    return nil   -- semua client
end


function run(cfg)
    cfg.reopen_sec  = cfg.reopen_sec or 300
    -- v7.51: matiin logcat streaming yang mungkin masih jalan dari sesi lama
    -- (nulis spam ke file). Loop grafis udah gantiin, gak perlu logcat streaming.
    pcall(function()
        os.execute("su -c 'pkill -f \"logcat -v threadtime\"' 2>/dev/null")
        os.execute("rm -f /sdcard/velium_logcat_live.log 2>/dev/null")
    end)
    if cfg.auto_rejoin == nil then cfg.auto_rejoin = true end
    cfg.auto_rejoin_menit = cfg.auto_rejoin_menit or 8
    cfg.disconnect_menit  = cfg.disconnect_menit or 3   -- v4.38: ngintip dialog error
    -- v4.73: bawaan NYALA (dulu 0/mati). Jendela nguncup jadi gelembung itu
    -- kejadian terus, dan sejak v4.63 ongkosnya cuma 1 panggilan su gabungan
    -- -- jadi murah. Isi 0 di config kalau mau dimatiin.
    cfg.jaga_depan_sec    = cfg.jaga_depan_sec or 3
    cfg.suplai_sec        = cfg.suplai_sec or 20        -- v4.54: jadwal cek suplai
    -- v5.37: bawaan NYALA (dulu mati). Cadangannya lengkap -- lihat catatan
    -- di setup. Config lama yang shell_tetap=false tetep dihormatin.
    if cfg.shell_tetap == nil then cfg.shell_tetap = true end
    cfg.autoexec_dir = cfg.autoexec_dir or "/sdcard/Delta/Autoexecute"
    cfg.poll_sec    = cfg.poll_sec or 5
    cfg.stagger_sec = cfg.stagger_sec or 15
    cfg.status_sec  = cfg.status_sec or 20
    cfg.win_mode    = cfg.win_mode or 0   -- config lama gak punya -> fullscreen, gak berubah perilaku
    -- v9.268: Arceus PAKSA win_mode=0. Arceus udah auto-freeform sendiri. Kalau worker
    -- ikut buka pake '--windowingMode 5', tiap activity (ProtocolLaunch + NativeMain)
    -- dapet bingkai freeform sendiri -> KOTAK DOBEL (bug user: "bingkai double").
    -- Arceus GAK butuh --windowingMode -- freeform-nya dari Arceus, bukan worker.
    if cfg.executor == "arceus" and (tonumber(cfg.win_mode) or 0) ~= 0 then
        cfg.win_mode = 0
        warn("Arceus: win_mode dipaksa 0 (Arceus auto-freeform; --windowingMode bikin bingkai DOBEL)")
    end
    -- v9.270: Arceus TETEP pake grid prefs App Cloner (itu yg bikin grid rapi -- kemarin
    -- selalu aman). Biang double kemarin = enable_freeform_support=1 (SISA eksperimen
    -- win_mode=5). Kalau support=1, Android IKUT gambar freeform di atas jendela App Cloner
    -- -> 2 bingkai. Support=0 = cuma App Cloner yg gambar = 1 bingkai + rapi (normal).
    -- Jadi buat Arceus: PASTIIN support=0 (bersihin leftover eksperimen kita).
    if cfg.executor == "arceus" then
        local ff = (sh("su -c 'settings get global enable_freeform_support'") or ""):gsub("%s+","")
        if ff == "1" then
            sh_silent("su -c 'settings put global enable_freeform_support 0'")
            sh_silent("su -c 'settings put global force_resizable_activities 0'")
            warn("Arceus: enable_freeform_support dimatiin (0) -> cegah bingkai DOBEL (App Cloner + Android freeform tabrakan)")
            ok("Arceus: pake grid prefs App Cloner (rapi) + support OFF (1 bingkai)")
        end
    end
    -- v4.34: nyalain mode deteksi longgar kalau diminta di config
    if cfg.deteksi_longgar == true then
        DETEKSI_LONGGAR = true
        warn("Deteksi LONGGAR nyala: ada ActivityRecord = dianggap jalan")
    end
    cfg.tunggu_sec  = cfg.tunggu_sec or 60
    -- v4.83: penanda layar KEY bisa ditambah dari config tanpa nyentuh worker:
    --   key_tanda="Kata A,Kata B"
    -- Berguna kalau Delta ganti tampilan -- gak usah nunggu worker diperbarui.
    if cfg.key_tanda and cfg.key_tanda ~= "" then
        local n = 0
        for _, t in ipairs(split(cfg.key_tanda)) do
            KEY_TANDA[#KEY_TANDA+1] = t; n = n + 1
        end
        if n > 0 then ok("Penanda layar KEY tambahan dari config: " .. n) end
    end
    -- v4.31: batas bawah. Di bawah 30 detik, Roblox di RF belum kelar loading ->
    -- tiap "ulang" nginterupsi loading yg lagi jalan -> gak pernah selesai (muter).
    if cfg.tunggu_sec < 30 then
        warn("tunggu_sec=" .. cfg.tunggu_sec .. " kekecilan buat RedFinger -> dipakai 30")
        cfg.tunggu_sec = 30
    end
    cfg.konfirmasi_sec = cfg.konfirmasi_sec or 90   -- v4.17: batas tunggu bridge konfirmasi masuk game
    cfg.orientasi   = cfg.orientasi or ""            -- v4.18: "" = jangan senggol orientasi
    if cfg.keep_alive == nil then cfg.keep_alive = true end   -- v4.18: config lama -> nyalain
    -- v4.28: suplai otomatis diatur TIM-1, dihitung sendiri dari nama tim.
    -- Gak usah ditanya pas setup, gak usah diinget di config -- jadi mustahil
    -- ada 2 RF yang rebutan ngatur (dulu itu bisa bikin akun gak balik ke PS asal).
    local timRingkas = (cfg.tim or ""):lower():gsub("[%s%-_]", "")
    cfg.suplai_master = (timRingkas == "tim1")
    -- v4.32: default NYALA. Kalau ternyata jendelanya fullscreen, atur_grid cuma
    -- gagal & kecatet di log -- gak ngerusak apa-apa.
    if cfg.auto_grid == nil then cfg.auto_grid = true end
    cfg.max_coba    = cfg.max_coba or 5
    cfg.tim         = cfg.tim or "tim-1"
    cfg.pkgs        = cfg.pkgs or cfg.roblox_pkg or "com.roblox.client"
    -- v5.24: nilai bawaan buat setelan yang bisa hilang kalau config disunting
    -- tangan. Tanpa ini, satu field kelupaan = worker mati pas nyala.
    cfg.targets     = cfg.targets or "FORCE"

    if not cfg.url or cfg.url:find("GANTI") or not cfg.kunci or cfg.kunci == "" then
        err("URL/Kunci belum diisi. Jalanin ulang, pilih E.")
        return
    end

    local list = split(cfg.pkgs)
    print(C.BOLD..C.G.."\n"..C.N)
    pcall(banner_velium)   -- sekali pas nyala (kuning, ASCII only, gak bisa gagalkan start)
    info("Tim   : "..cfg.tim.." ("..#list.." client)")
    -- v8.31: DETEKSI VERSI BARU + auto-restart client DIBUANG (v8.26). User: auto-
    -- update bikin error -- OUT semua client + buka ulang malah kacau (1/10 tiba2
    -- jalan). Update worker gak usah auto-restart client; client dibiarin, FORCE
    -- manual dari panel kalau mau nyalain versi baru.
    -- v5.21: peringatan "3 baris gak muat" DICABUT -- ternyata SALAH.
    -- Kalibrasi manual di 9 client emang gagal (tombolnya susah dilihat/dipencet
    -- tangan di jendela ~173px), tapi sapuan otomatis KENA: 0.833, 0.808.
    -- Jadi 3 baris tetep bisa dipakai bypass. Yang batesin cuma RAM.
    info("Panel : "..cfg.url)
    info("Pemicu: "..cfg.targets.." | poll "..cfg.poll_sec.."s")

    -- v4.1: freeform butuh setelan sistem. Kalau ini mati, --windowingMode 5
    -- DITERIMA tapi diem-diem gak ngefek -> kebuka fullscreen, gak ada error.
    -- Ini jebakan paling nyebelin: keliatan jalan padahal nggak.
    local wm = tonumber(cfg.win_mode) or 0
    if wm == 5 then
        local ff = sh("su -c 'settings get global enable_freeform_support'"):gsub("%s+","")
        if ff ~= "1" then
            warn("enable_freeform_support = "..(ff == "" and "null" or ff).." -> freeform MATI di sistem")
            info("Nyalain...")
            sh_silent("su -c 'settings put global enable_freeform_support 1'")
            local cek = sh("su -c 'settings get global enable_freeform_support'"):gsub("%s+","")
            if cek == "1" then
                ok("freeform dinyalain")
                warn("Sebagian device baru ngefek abis restart.")
            else
                err("Gagal nyalain. Root beneran jalan?")
            end
        else
            ok("enable_freeform_support = 1")
        end

        local fr = sh("su -c 'settings get global force_resizable_activities'"):gsub("%s+","")
        if fr ~= "1" then
            info("force_resizable_activities = "..(fr == "" and "null" or fr))
            info("Kalau Roblox nolak freeform, coba: settings put global force_resizable_activities 1")
        end
    end

    info("Window: "..(wm == 5 and "freeform (5)" or wm == 6 and "multi-window (6)" or "fullscreen (bawaan)"))

    -- tes sambungan dulu, biar gak diem-diem gagal berjam-jam
    local tes = api_get(cfg, "/perintah?tim=" .. cfg.tim)
    if tes == "" then
        err("Gak nyambung ke panel. Cek URL / internet.")
        return
    end
    local kesalahan = ambil_str(tes, "error")
    if kesalahan then
        err("Panel nolak: " .. kesalahan)
        if kesalahan:find("kunci") then err("Kunci beda sama `wrangler secret put KUNCI`.") end
        return
    end
    ok("Nyambung ke panel")

    -- v5.40: benerin skrip `up` kalau ketinggalan. Ini yang bikin RF lama
    -- nyangkut di versi tua: `up`-nya dibikin sekali pas pasang, terus gak
    -- pernah diperbarui -- dan dia bilang "OK", bukan gagal.
    pcall(tulis_skrip_up)

    -- v5.32: TARIK KUNCI API SEKARANG, bukan nanti pas dibutuhin.
    -- Alasannya: `velium key` dipanggil justru pas lisensi Delta abis -- saat
    -- paling genting. Kalau baru narik di situ dan panel lagi mati, bypass
    -- gagal. Ditarik di awal + disimpen ke config = pas dibutuhin udah lokal,
    -- instan, dan gak bergantung panel sama sekali.
    do
        local k, asal = ambil_apikey(cfg)
        if k ~= "" then
            info("Kunci API bypass siap (dari " .. asal .. ")")
        else
            warn("Kunci API bypass belum ada -- `velium key` bakal gagal.")
            warn("  Isi BYPASS_KEY_BAWAAN di worker, atau: velium key set <APIKEY>")
        end
    end

    tulis_autoexec(cfg)   -- v4.8: pasang loader ke autoexec Delta

    -- v4.18: kunci orientasi (kalau diset) + keep-alive awal
    if cfg.orientasi == "landscape" or cfg.orientasi == "portrait" then
        set_orientasi(cfg); ok("Orientasi dikunci: " .. cfg.orientasi)
    end
    -- v4.70: nyalain shell root tetap (kalau diminta). Gagal = lanjut cara lama.
    if cfg.shell_tetap == true then
        local ok2, sebab = shell_nyalakan()
        if ok2 then
            ok("Shell root tetap NYALA -- 'su' cuma dibuka sekali")
        else
            warn("Shell root tetap gagal (" .. (sebab or "?") .. ") -> pakai cara lama")
        end
    end

    -- v4.21: wake-lock CPU (biar worker gak ditidurin pas layar idle)
    sh_silent("termux-wake-lock")
    if cfg.suplai_master then
        ok("tim-1 -> RF ini yang mancing suplai otomatis")
    end
    -- v4.30: kasih tau kenapa auto grid mati, biar gak bingung nunggu-nunggu
    if cfg.auto_grid ~= true then
        warn("AUTO GRID mati di config. Nyalain: setup ulang (rm velium_worker_config.lua)")
    else
        ok("Auto grid nyala")
    end
    if cfg.keep_alive ~= false then
        keep_alive_apply(cfg)
        -- v4.22: freezer-disable DICABUT. dulu dikira client "off" karena Android
        -- bekuin proses -- SALAH: game-nya jalan normal, yg berhenti cuma LAPORAN
        -- (bug jarak denyut di bridge, udah dibenerin di star_farm v13.10 +
        -- market v8.336). matiin freezer malah nambah beban CPU -> task.wait di
        -- script makin molor -> laporan makin telat. jadi jangan disenggol.
        ok("Keep-alive (anti-FC) nyala")
    end

    -- v4.9: cache mapping client<->akun (baca prefs.xml sekali di awal, refresh berkala).
    -- prefs.xml jarang berubah (akun tetap per client), jadi gak usah baca tiap loop.
    local mapAkun = {}   -- pkg -> username
    -- v4.62: baca username SEMUA client dalam SATU panggilan su. Dulu satu-satu
    -- (4 client = 4 x ~5 detik = ~20 detik tiap refresh).
    local function refresh_map()
        local lama = {}
        for pkg, u in pairs(mapAkun) do lama[pkg] = u end   -- v9.243: snapshot buat deteksi akun baru/ganti
        local pkgs = split(cfg.pkgs)
        local perintah = {}
        for _, pkg in ipairs(pkgs) do
            perintah[#perintah+1] = string.format(
                'echo "@@%s"; cat /data/data/%s/shared_prefs/prefs.xml 2>/dev/null', pkg, pkg)
        end
        local o = sh("su -c '" .. table.concat(perintah, "; ") .. "'") or ""
        -- pisah per penanda @@<paket>
        local skrgPkg = nil
        for baris in o:gmatch("[^\r\n]+") do
            local tanda = baris:match("^@@(%S+)")
            if tanda then
                skrgPkg = tanda
            elseif skrgPkg then
                local u = baris:match('<string name="username">(.-)</string>')
                if u then mapAkun[skrgPkg] = u; skrgPkg = nil end
            end
        end
        -- cadangan: kalau ada yang gak kebaca, ambil satu-satu (jarang)
        for _, pkg in ipairs(pkgs) do
            if not mapAkun[pkg] then
                local u = baca_username(pkg)
                if u then mapAkun[pkg] = u end
            end
        end
        -- v9.243: deteksi ada username yang BERUBAH (akun baru dibuat / ganti akun di client).
        -- Kalau ada -> caller langsung auto_assign (gak nunggu siklus 3 menit).
        local berubah = false
        for pkg, u in pairs(mapAkun) do
            if lama[pkg] ~= u then berubah = true; break end
        end
        return berubah
    end
    refresh_map()
    local lastMapRefresh = os.time()

    -- v4.14: auto-assign akun ke tim. worker kirim daftar akun yg dia pegang
    -- (dari mapAkun) ke panel -> panel tau akun ini di tim mana OTOMATIS.
    -- mode isi_kosong: gak nimpa assign manual di panel.
    local function auto_assign_tim()
        local akun = {}
        for _, ak in pairs(mapAkun) do akun[#akun+1] = ak end
        if #akun == 0 then return end
        local body = '{"tim":"' .. cfg.tim .. '","game":"' .. (cfg.game_label or "") ..
                     '","isi_kosong":true,"akun":['
        for i, a in ipairs(akun) do
            body = body .. '"' .. a .. '"'
            if i < #akun then body = body .. "," end
        end
        body = body .. "]}"
        local r = ""
        pcall(function()
            r = api_post(cfg, "/assign-tim", body) or ""
        end)
        -- v5.43: lapor apa yang DIBETULIN, bukan cuma jumlahnya.
        -- Perlu karena akun bekas game lain itu masalah yang membingungkan:
        -- timnya bener tapi gak nongol di tab yang bener, dan gak ada tanda
        -- apa pun. Sekarang keliatan pas dibetulin.
        local nG = tonumber((r or ""):match('"gameDiperbarui"%s*:%s*(%d+)')) or 0
        local nP = tonumber((r or ""):match('"placeDibersihin"%s*:%s*(%d+)')) or 0
        -- v5.44: akun yang DIREBUT dari tim lain dilaporin satu-satu.
        -- Penting: kalau satu akun kepasang di client DUA RF, dua worker bakal
        -- tarik-menarik -- dan itu bakal keliatan di sini tiap 10 menit. Kalau
        -- baris ini muncul terus buat akun yang sama, berarti akunnya kepasang
        -- ganda dan harus dibenerin di RF-nya.
        local dipindah = {}
        for nm, dari in (r or ""):gmatch('"nama"%s*:%s*"(.-)"%s*,%s*"dari"%s*:%s*"(.-)"') do
            dipindah[#dipindah+1] = nm .. " (dari " .. dari .. ")"
        end
        if #dipindah > 0 then
            warn("akun DIREBUT ke " .. cfg.tim .. ": " .. table.concat(dipindah, ", "))
            warn("  kalau ini muncul TERUS buat akun yang sama -> akunnya kepasang di 2 RF")
        end
        if nG > 0 or nP > 0 then
            ok(("auto-assign %d akun ke %s  (%d game dibetulin, %d place basi dibuang)")
                :format(#akun, cfg.tim, nG, nP))
            info("  akun ini bekas game lain -- sekarang kecatat di " .. (cfg.game_label or "?"))
        else
            ok("auto-assign " .. #akun .. " akun ke " .. cfg.tim)
        end
    end
    auto_assign_tim()
    local lastAssign = os.time()

    -- v4.11: assign PS per-client. narik dari panel /assign-ps?tim=X.
    -- hasilnya: mapLink[pkg]=link (buat buka client ke PS-nya),
    --           mapPsNama[pkg]=nama (buat tampil di tabel).
    local mapLink, mapPsNama = {}, {}
    local function refresh_ps()
        local r = api_get(cfg, "/assign-ps?tim=" .. cfg.tim)
        -- format: {"assign":[{"akun":"fifinx_5","ps_nama":"leveling 1","link":"..."},...]}
        -- cocokin akun -> pkg (lewat mapAkun kebalik)
        local akun2pkg = {}
        for pkg, ak in pairs(mapAkun) do akun2pkg[ak] = pkg end
        mapLink, mapPsNama = {}, {}
        -- parse tiap objek assign
        for obj in (r or ""):gmatch('{.-}') do
            local akun = obj:match('"akun"%s*:%s*"(.-)"')
            local psn  = obj:match('"ps_nama"%s*:%s*"(.-)"')
            local link = obj:match('"link"%s*:%s*"(.-)"')
            if akun and akun2pkg[akun] then
                local pkg = akun2pkg[akun]
                if link and link ~= "" then mapLink[pkg] = link end
                if psn and psn ~= "" then mapPsNama[pkg] = psn end
            end
        end
    end
    refresh_ps()
    -- v7.36: GABUNG PS LINK dari getps (per akun, disimpen backend kolom ps_link).
    -- Kalau akun punya ps_link (accessCode=UUID dari velium getps), pakai itu buat
    -- masuk PS pribadi akun. Prioritas: assign-ps panel > ps_link getps > public.
    local function refresh_ps_getps()
        -- v9.180: skip getps CUMA kalau public (pakai_ps==false). Dulu skip W1
        -- (place==129343810645058) SELALU -> W1 gak pernah ambil PS -> public. Skrg
        -- W1 private (pakai_ps=true dari server) IKUT getps -> ambil W1 PS accessCode.
        if cfg.pakai_ps == false then return end
        -- v9.97: mode SERVER CUSTOM -> semua akun ke 1 link (_ps_override), gak perlu
        -- getps per-akun. Skip biar gak buang waktu ambil accessCode yg gak kepakai.
        if (SERVER_TERAKHIR or ""):lower() == "custom" and cfg._ps_override and cfg._ps_override ~= "" then
            return
        end
        local r = api_get(cfg, "/ps-list") or ""
        local akun2pkg = {}
        for pkg, ak in pairs(mapAkun) do akun2pkg[ak] = pkg end
        local nDapet = 0
        for obj in r:gmatch('{.-}') do
            local akun = obj:match('"akun"%s*:%s*"(.-)"')
            local psl  = obj:match('"ps_link"%s*:%s*"(.-)"')
            if akun and akun2pkg[akun] and psl and psl ~= "" then
                local pkg = akun2pkg[akun]
                -- v9.297: ps_link bisa "accessCode=X|share=Y" -> buang bagian share
                -- (itu buat panel/mobile). Worker join pakai accessCode aja.
                psl = psl:gsub("|share=.*$", "")
                if not mapLink[pkg] then mapLink[pkg] = psl; nDapet = nDapet + 1 end
            end
        end
        -- v8.53: log berapa akun dapet accessCode (biar keliatan ps_link ada/kosong)
        info(("[ps-getps] %d akun dapet ps_link (place=%s)"):format(nDapet, cfg.place_id or "?"))
        -- v8.71: kalau 0 dapet PS + place FALL (bukan public/W1) -> WARNING jelas.
        -- Akun belum punya PS fall -> bakal fallback PUBLIC (rawan di-steal).
        -- Saran: jalanin `velium getps` di RF ini buat ambil accessCode PS akun.
        if nDapet == 0 and cfg.pakai_ps ~= false then
            -- v9.129: AUTO-getps DIBUANG dari loop utama (user minta getps MANUAL).
            -- Dulu di sini auto jalanin 'velium getps' (timeout 180 = block 3 menit)
            -- tiap 5 menit kalau 0 PS -> bikin loop utama macet + ganggu rotasi.
            -- Sekarang cuma BACA /ps-list. Kalau 0 PS -> warning, user getps manual.
            warn("[ps-getps] 0 ps_link -> jalanin 'velium getps' MANUAL di RF ini dulu (auto-getps udah dimatiin).")
        end
        if nDapet == 0 and cfg.pakai_ps ~= false then
            warn("[ps-getps] 0 akun punya PS -> client bakal masuk PUBLIC (rawan)!")
            warn("[ps-getps] Jalanin 'velium getps' di RF ini dulu, atau assign PS di panel.")
        end
    end
    pcall(refresh_ps_getps)
    local lastPsRefresh = os.time()

    -- v4.10: tampilan TABEL (clear screen + redraw kiri atas, gak scroll spam).
    -- log penting (auto-rejoin/error) ditaro di buffer, muncul di bawah tabel.
    local logBuf = {}   -- ring buffer log terakhir
    local function tambahLog(msg)
        local baris = os.date("%H:%M:%S") .. " " .. msg
        logBuf[#logBuf+1] = baris
        while #logBuf > 6 do table.remove(logBuf, 1) end   -- simpan 6 terakhir
        catatKirim(baris)   -- v4.24: ikut dikirim ke panel
    end

    -- v4.16: CACHE status client + ram/cpu. dulu gambar_tabel manggil pkg_running
    -- (dumpsys, LAMBAT) buat tiap client TIAP redraw -> tabel lelet. sekarang status
    -- di-refresh berkala di background, tabel cuma baca cache -> redraw INSTAN.
    local cacheRun = {}    -- pkg -> true/false (ada jendela di layar?)
    local cacheHidup = {}  -- v5.45: pkg -> true/false (prosesnya idup?)
    local runSebelum = {}  -- v4.46: status ronde lalu, buat nangkep yang MATI MENDADAK
    local bekuSejak = {}   -- v6.15: kapan client mulai beku (script gak lapor)
    local cacheBridge = {} -- v4.49: script beneran lapor apa nggak (bukan cuma window ada)
    local cacheRam = {0,0,0}
    local cacheCpu = 0
    local lastStatusCek = 0
    local function refresh_status()
        -- v4.63: satu dump buat semua client (dulu satu-satu -> ~24 detik)
        local semua, hidupMap = pkg_running_semua(split(cfg.pkgs))
        for _, pkg in ipairs(split(cfg.pkgs)) do
            cacheRun[pkg] = semua[pkg]
            -- v5.45: proses idup tapi jendela gak ada = "latar", bukan "off"
            cacheHidup[pkg] = hidupMap and hidupMap[pkg] or false
        end
        -- v4.49: "ada di layar game" BEDA sama "script beneran jalan". Jendela
        -- yang dikuncupin jadi gelembung tetep punya activity -> ke-baca jalan
        -- padahal diem. Yang tau sebenernya cuma bridge (script lapor apa nggak).
        local st = api_get(cfg, "/stat")
        for _, pkg in ipairs(split(cfg.pkgs)) do
            local ak = mapAkun[pkg]
            cacheBridge[pkg] = ak and bridge_fresh(st, ak) or false
        end
        local u, f, t = baca_ram()
        cacheRam = {u, f, t}
        cacheCpu = baca_cpu()
    end
    -- v4.16: JANGAN refresh_status blocking di awal (dumpsys semua client = lama).
    -- biarin cache kosong dulu -> tabel langsung muncul (status "cek..."), status
    -- nyusul di loop pertama. jadi tabel muncul INSTAN, gak nunggu dumpsys.
    for _, pkg in ipairs(split(cfg.pkgs)) do cacheRun[pkg] = nil end
    local function gambar_tabel(isi, statusPerintah)
        -- v6.90: DEFAULT skip tabel -- cuma LOG yang numpuk (gak dihapus/clear).
        -- User minta log jangan ke-clear terus (tabel gak penting, status client
        -- ada di panel). Dulu tabel di-redraw + clear screen tiap 5s -> log lama
        -- keilangan. Sekarang tabel gak digambar, clear screen gak jalan -> log
        -- numpuk terus (bisa discroll & disalin). Mau tabel balik? set VELIUM_TABEL=1.
        if os.getenv("VELIUM_TABEL") ~= "1" then
            return   -- skip tabel + skip clear screen; log numpuk terus
        end
        io.write("\27[2J\27[H")   -- clear screen + kursor ke kiri atas
        local used, free, total = cacheRam[1], cacheRam[2], cacheRam[3]
        local cpu = cacheCpu
        -- header
        -- v5.35: script yang aktif ikut ditampilin. Perlu karena satu tim GAG 2
        -- bisa jalanin STAR FARM atau STAR SEED -- tanpa ini gak keliatan yang
        -- mana, dan salah script itu gejalanya membingungkan (client jalan tapi
        -- gak ngapa-ngapain).
        local scLabel = cfg.script_label or ""
        if scLabel == "" and (cfg.script_url or "") ~= "" then
            scLabel = tostring(cfg.script_url):match("([^/]+)$") or ""
        end
        io.write(C.BOLD..C.G.."  VELIUM WORKER v"..VERSION.."  Â·  "..cfg.tim.."  Â·  "..(cfg.game_label or "")..C.N
            ..(scLabel ~= "" and (C.D.."  Â·  "..C.C..scLabel..C.N) or "").."\n")
        io.write(C.D.."  "..os.date("%H:%M:%S").."  Â·  perintah: "..(isi ~= "" and isi or "-").."\n"..C.N)
        io.write("\n")
        -- tabel
        local list = split(cfg.pkgs)
        local jalan = 0
        io.write(C.D.."  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”\n"..C.N)
        io.write(C.D.."  â”‚ "..C.N.."CLIENT   "..C.D.."â”‚ "..C.N.."AKUN           "..C.D.."â”‚ "..C.N.."SERVER     "..C.D.."â”‚ "..C.N.."STATUS   "..C.D.."â”‚\n"..C.N)
        io.write(C.D.."  â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤\n"..C.N)
        local beku = 0
        for _, pkg in ipairs(list) do
            local run = cacheRun[pkg]
            -- v4.49: yang kehitung "jalan" cuma yang script-nya BENERAN lapor.
            -- window ada tapi diem (dikuncupin/beku) dihitung terpisah.
            if run and cacheBridge[pkg] == false and mapAkun[pkg] then
                beku = beku + 1
            elseif run then jalan = jalan + 1 end
            local short = pkg:gsub("com%.roblox%.", "")   -- clienu
            local akun = mapAkun[pkg] or "?"
            local srv = mapPsNama[pkg] or "public"
            local st, warna
            if run == nil then st, warna = "â—Œ cek...", C.D      -- belum kecek
            elseif run and cacheBridge[pkg] == false and mapAkun[pkg] then
                -- window-nya ada tapi script gak lapor -> dikuncupin / beku
                st, warna = "â— beku", C.Y
            elseif run then st, warna = "â— jalan", C.G
            elseif cacheHidup[pkg] then
                -- v5.45: prosesnya IDUP tapi jendelanya gak ada. Beda dari mati:
                -- ini HARUS ditutup dulu sebelum dibuka, dan itu yang bikin log
                -- "tutup paksa" muncul buat client yang keliatan "off".
                st, warna = "â— latar", C.C
            else st, warna = "â—‹ off", C.Y end
            -- v5.34: nama akun dipotong dari DEPAN, bukan belakang.
            -- Pola nama akun itu awalan+nomor (wildnx_12, oliviainvent3), jadi
            -- yang MEMBEDAKAN ada di ujung belakang. Motong dari belakang bikin
            -- 4 akun beda keliatan sama persis ("oliviainvent" itu pas 12
            -- huruf) -- dan itu nyesatin: keliatannya kayak 4 client login ke
            -- satu akun yang sama, padahal cuma kepotong.
            local akunTampil = akun
            if #akunTampil > 14 then akunTampil = "â€¦" .. akunTampil:sub(-13) end
            io.write(string.format("  "..C.D.."â”‚ "..C.N.."%-8s "..C.D.."â”‚ "..C.N.."%-14s "..C.D.."â”‚ "..C.C.."%-10s"..C.D.." â”‚ "..warna.."%-8s"..C.D.." â”‚\n"..C.N,
                short:sub(1,8), akunTampil, srv:sub(1,10), st))
        end
        io.write(C.D.."  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”´â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜\n"..C.N)
        io.write("\n")
        -- ringkas
        io.write(string.format("  "..C.G.."%d/%d jalan"..C.N.."%s  Â·  CPU %d%%  Â·  RAM %.1f/%.1fGB\n",
            jalan, #list,
            beku > 0 and (C.Y.."  Â·  "..beku.." beku"..C.N) or "",
            cpu, used, total))
        -- v5.30: status laporan ke panel. Kalau ini GAGAL, tim bakal keliatan
        -- KOSONG di panel walau worker-nya sendiri jalan normal.
        if LAPOR_OK == false then
            io.write("  "..C.R.."LAPOR KE PANEL GAGAL: "..tostring(LAPOR_SEBAB or "?")..C.N.."\n")
            io.write("  "..C.D.."   -> makanya tim ini kosong di panel"..C.N.."\n")
        elseif LAPOR_OK == true then
            local umur = os.time() - (LAPOR_TS or 0)
            io.write("  "..C.D.."panel: kekirim "..umur.."s lalu"..C.N.."\n")
        else
            io.write("  "..C.D.."panel: belum pernah lapor"..C.N.."\n")
        end
        -- log
        if #logBuf > 0 then
            io.write("\n"..C.D.."  â”€â”€ log â”€â”€\n"..C.N)
            for _, l in ipairs(logBuf) do io.write(C.D.."  "..l.."\n"..C.N) end
        end
        io.flush()
    end

    notify("Velium "..cfg.tim, "Standby â€” nungguin: "..cfg.targets)

    local lastOpen, lastStatus = 0, 0
    local lastAutoRejoin = 0   -- v4.9: kapan terakhir cek auto-rejoin
    local lastKeepAlive = os.time()   -- v4.18: kapan terakhir apply keep-alive
    local psGantiKerjakan = 0   -- v4.51: psGanti terakhir yang UDAH dikerjain
    -- v5.29: script per tim dari panel
    local SCRIPT_KERJAKAN  = 0    -- scriptGanti terakhir yang udah dikerjain
    local SCRIPT_URL_AKHIR = ""   -- url terakhir yang beneran ditulis ke autoexec
    local lastJagaDepan = 0     -- v4.52: kapan terakhir munculin ulang jendela
    local lastRekamDc = 0       -- v7.29: kapan terakhir rekam disconnect dari logcat
    local lastSuplaiCek = 0     -- v4.54: kapan terakhir minta CF ngerencanain suplai
    local lastLisensiCek = 0   -- v6.14: kapan terakhir cek lisensi berkala
    local LISENSI_CEK_TS = 0   -- v9.239: kapan terakhir cek lisensi PRIORITAS (top-loop, tiap 60s)
    local lastSettingCek = 0   -- v9.34: kapan terakhir cek /setting-tim (tiap 5s)
    local lastCekGrafis = 0    -- v8.12: kapan terakhir cek all grafis (tiap 90s)
    local lastCekCaptcha = 0   -- v6.55: kapan terakhir cek captcha berkala
    local lastCookieStandby = 0  -- v6.84: kapan terakhir cek cookie pas standby
    local lastPendingLog = 0     -- v6.92: kapan terakhir log "nunggu ganti akun"
    local waktuAktivitas = 0     -- v6.95: kapan terakhir ada aktivitas ganti akun/LOGIN
    local lastCooldownLog = 0    -- v6.95: kapan terakhir log cooldown 3 menit
    -- v9.41: track ts RESTART terakhir diproses. Inisialisasi dari ts perintah AWAL
    -- biar RESTART BASI (bekas di DB, ts lama) pas worker baru jalan GAK keproses --
    -- cuma RESTART BARU (ts naik = pencet Start baru) yg jalan. Fix loop restart.
    local lastRestartTs = 0
    do
        local rAwal = api_get(cfg, "/perintah?tim=" .. cfg.tim)
        local iAwal = (ambil_str(rAwal, "isi") or ""):upper()
        -- kalau perintah awal udah RESTART (bekas) -> catat ts-nya biar gak keproses
        if iAwal:find("RESTART") then
            lastRestartTs = ambil_num(rAwal, "ts") or 0
            RESTART_TS_PROSES = lastRestartTs   -- v9.77: tandai udah diproses
            info("RESTART lama di DB (ts=" .. lastRestartTs .. ") -- diabaikan (bukan restart baru)")
        end
    end
    local nudgeCnt = {}   -- v4.21: berapa kali client di-nudge (bangunin) tanpa sembuh
    local lastIsi = nil
    -- v8.61: MODE_JALAN = state persisten (true=lagi jalan/FORCE, false=standby).
    -- BUG yg difix: PLACE:/GRID: NIMPA perintah STANDBY di `isi`. `mati` dicek dari
    -- `isi` sekarang doang -> pas isi jadi "PLACE:..." (bukan STANDBY), mati=false
    -- -> worker anggap JALAN -> buka client walau harusnya standby. Sekarang
    -- MODE_JALAN cuma berubah pas FORCE (->true) / STANDBY/STOP (->false). PLACE/
    -- GRID gak ubah -> standby tetep standby.
    local MODE_JALAN = false

    -- v9.89: PULIHIN state aktif (server + grid + daftar client) dari file lokal
    -- SEBELUM lapor awal + loop. Biar abis UPDATE/REBOOT worker buka PERSIS yg
    -- tadi jalan (6 client), gak balik ke semua (10) + grid campur.
    do
        local ok2, n, place, gk = pulih_aktif(cfg)
        if ok2 then
            PKGS_AKTIF_PULIH = true   -- udah pulih dari file -> gak usah baca start-pilih lagi
            info(("[boot] pulih state aktif: %d client, place=%s, grid=%s kolom"):format(
                n, tostring(place ~= "" and place or cfg.place_id), gk and gk > 0 and tostring(gk) or "auto"))
        end
    end

    -- v9.96: BOOT PAKAI LOGIKA START PAKSA. User: abis UPDATE/REBOOT, pas awal
    -- nyala harus se-anti-gagal Start Paksa -- PS/grid/client PASTI bener, gak
    -- kadang public / grid campur. Reset fresh (kayak PAKSA handler): grid cache
    -- kosong (grid dihitung ulang buat daftar bener) + getps guard dibuang (getps
    -- JALAN FRESH -> ps_link ke-ambil ulang -> PS private, gak fallback public).
    -- PKGS_AKTIF (daftar client) TETEP dari pulih_aktif -> buka PERSIS yg tadi.
    do
        SUDAH_GRID = false; GRID_CACHE = nil
        if KICK_DIURUS then KICK_DIURUS["getps_jalan"] = nil end   -- getps jalan fresh pas boot
        info("[boot] mode START PAKSA -- grid fresh + getps ulang (PS/grid pasti bener)")
        ROTASI_SIAP_TS = 0   -- v9.116: tim 1 belum kebentuk -> tunggu lagi sebelum rotasi
        -- v9.106: pastiin launcher velium mode LOOP (buat RF lama) -> auto-update mulus
        pcall(tulis_launcher_loop)
    end

    -- v6.83: LAPOR AWAL sebelum loop -- scan client + akun, kirim ke panel
    -- LANGSUNG (gak nunggu 20 detik lapor rutin / gak nunggu FORCE). Biar panel
    -- gak KOSONG pas worker baru jalan / standby -> user bisa langsung ganti akun.
    do
        info("Lapor awal ke panel (client + akun)...")
        refresh_status()   -- isi cacheRun (client nyala apa nggak)
        local isiAwal = api_get(cfg, "/perintah?tim=" .. cfg.tim)
        local ia = ambil_str(isiAwal, "isi") or ""
        lapor(cfg, ia, cacheRun)   -- kirim daftar client + akun ke panel
        lastStatus = os.time()
    end

    -- v9.25: AMBIL SETTING PERSISTEN dari panel (place/grid/client). User: worker
    -- pas mulai harusnya cek panel -- setting PS/kolom/client berubah gak. Simpan
    -- persisten di backend (/setting-tim), gak cuma perintah 1-slot yg ke-nimpa.
    -- Kalau setting BERUBAH dari config lokal -> set + tandain perlu RESTART biar
    -- kepakai bersih. Kalau SAMA -> jalan biasa (gak ganggu client jalan).
    do
        local rS = api_get(cfg, "/setting-tim?tim=" .. cfg.tim)
        local sPlace = ambil_str(rS, "place") or ""
        local sGrid = ambil_num(rS, "grid") or 0
        SETTING_TS_TERAKHIR = ambil_num(rS, "ts") or 0   -- v9.26: baseline ts
        SERVER_TERAKHIR = ambil_str(rS, "server") or ""   -- v9.62: baseline server
        local berubah = false
        if sPlace ~= "" and sPlace ~= cfg.place_id then
            info(("Setting panel: place %s (beda dari %s) -- kepakai"):format(sPlace, tostring(cfg.place_id)))
            cfg.place_id = sPlace
            berubah = true
        end
        if sGrid > 0 and sGrid ~= (tonumber(cfg.grid_kolom) or 0) then
            info(("Setting panel: grid %d kolom (beda dari %d) -- kepakai"):format(sGrid, tonumber(cfg.grid_kolom) or 0))
            cfg.grid_kolom = sGrid
            berubah = true
        end
        if berubah then
            pcall(function() save_config(cfg) end)
            SUDAH_GRID = false; GRID_CACHE = nil
            info("Setting dari panel BERUBAH -> kepakai pas Start (grid/place fresh)")
        else
            info("Setting panel sama kayak config -- gak ada perubahan")
        end
    end

    -- v7.62: (banner karamel dihapus -- banner_velium yg kepakai)

    while true do
        -- ===== v4.2: pintu keluar =====
        if ada_stop() then
            bersih(cfg, "diminta stop")
            return
        end

        -- v9.164: AUTO-UPDATE DELTA DIMATIIN default. Dulu (v9.100) jalan tiap 10
        -- menit -> download 6-20 client x110MB NGE-BLOK loop (client gak kebuka,
        -- worker keliatan hang). Dulu ke-tutupin karena nama file salah -> 404 cepet.
        -- Sekarang nama file udah bener (v9.163) -> download beneran jalan -> blok.
        -- Update client pakai MANUAL: `velium update clien`. Auto cuma kalau
        -- cfg.auto_delta di-set (jarang).
        if cfg.auto_delta and os.time() - DELTA_CEK_TS >= 600 then
            DELTA_CEK_TS = os.time()
            local target = cek_delta_versi(cfg)
            if target and target ~= "" then
                -- versi terpasang di client pertama
                local pkg1 = split(cfg.pkgs or "")[1]
                local vNow = ""
                if pkg1 then
                    local out = sh(("su -c 'dumpsys package %s 2>/dev/null | grep -m1 versionName' 2>/dev/null"):format(pkg1)) or ""
                    vNow = out:match("versionName=([%w%.%-]+)") or ""
                end
                if vNow ~= "" and vNow ~= target then
                    info(("[delta] versi baru di GitHub: v%s (sekarang v%s) -> auto-update"):format(target, vNow))
                    pcall(function() update_delta_ke(cfg, target) end)
                    info("[delta] auto-update selesai -> client bakal rejoin fresh")
                    -- abis update, tandai perlu rejoin (Delta ke-reinstall, client mati)
                    SUDAH_GRID = false; GRID_CACHE = nil
                end
            end
        end

        -- v9.111: AUTO-UPDATE WORKER DIMATIIN (beresiko: 1 bug matiin semua RF
        -- sekaligus). Ganti pakai tombol UPDATE-WORKER dari panel (manual, bisa
        -- test 1 RF dulu). cek_worker_versi tetep ada -> dipanggil dari handler panel.

        -- v8.33: CEK GRAFIS di TOP loop (level atas, PASTI jalan tiap iterasi).
        -- Loop grafis lama ke-nest DALAM FORCE handler (depth 4) -> gak jalan
        -- kalau client udah kebuka semua (alur gak nyampe). Taruh di sini biar
        -- lepas dari buka-client. Cek DENYUT tiap 30s: denyut mati >2 menit -> langsung rejoin (gak nunggu siklus lama).
        do
            local respTop = api_get(cfg, "/perintah?tim=" .. cfg.tim)
            local isiTop = ambil_str(respTop, "isi") or ""
            -- v9.239: LISENSI = PRIORITAS MUTLAK (di ATAS stock/apapun). Cek tiap 60s.
            -- Kalau Delta HILANG -> paksa bypass LANGSUNG (reset gate) + SKIP proses stock
            -- ronde ini. Percuma rotasi kalau client nyangkut layar key. Lisensi balik
            -- dulu, baru urus stock. User: lisensi lebih utama dari perintah apapun.
            local skipKarenaLisensi = false
            if MODE_JALAN and (os.time() - (LISENSI_CEK_TS or 0)) >= 60 then
                LISENSI_CEK_TS = os.time()
                if lisensi_keadaan(cfg) ~= "ada" then
                    warn("[LISENSI] Delta HILANG -- PRIORITAS MUTLAK: pulihin DULU, skip stock ronde ini")
                    lastLisensiCek = 0        -- paksa cek+bypass lisensi di blok bawah (gak nunggu 10 menit)
                    BYPASS_TERAKHIR = 0       -- reset gate 60s -> bypass boleh LANGSUNG
                    skipKarenaLisensi = true
                end
            end
            -- v9.137: SINYAL TEST diproses LANGSUNG di top-loop (gak nunggu dispatch di
            -- bawah yg telat kalau worker sibuk denyut/open). Jadi test langsung masuk.
            if not skipKarenaLisensi and isiTop:upper():find("ROTASI%-TEST") and isiTop ~= ROTASI_TEST_LAST then
                ROTASI_TEST_LAST = isiTop
                warn("[rotasi] >>> SINYAL TEST (top-loop, LANGSUNG) <<<")
                tambahLog("Rotasi TEST: sinyal palsu (langsung)")
                if ROTASI_STATE == "idle" then
                    pcall(function() jalankan_rotasi(cfg, "TEST-PALSU", mapLink) end)
                else
                    warn("[rotasi] rotasi lagi jalan -> skip test")
                end
            end
            -- v9.139: SINYAL STOCK dari PANEL (real-time detect di browser). Panel
            -- deteksi seed restock -> kirim ROTASI-GO -> worker langsung rotasi (respect
            -- gate tim 1 siap + cooldown). Lebih cepet dari worker poll sendiri.
            if not skipKarenaLisensi and isiTop:upper():find("ROTASI%-GO") and isiTop ~= ROTASI_GO_LAST then
                ROTASI_GO_LAST = isiTop
                -- v9.195: extract DUNIA (place) dari sinyal ROTASI-GO|seed|ts|place.
                -- Panel kirim place sesuai dunia seed (Dunia1=W1, Dunia2=W2) -> tim 2
                -- borong di dunia SEED, bukan dunia tim 1.
                -- v9.200: extract SEED juga -> log tau stock APA (bukan cuma "PANEL-STOCK").
                local seedGO = isiTop:match("ROTASI%-GO|([^|]*)|") or "?"
                local placeGO = isiTop:match("ROTASI%-GO|[^|]*|[^|]*|(%d+)")
                -- v9.226: extract ts panel (field ke-3) -> hitung DELAY (worker baca -
                -- panel kirim). Delay tinggi = ke-BLOCK (worker sibuk). Delay rendah =
                -- fresh (panel baru kirim). Buat diagnosa "stock telat" ke-block/panel-lambat.
                local tsGO = tonumber(isiTop:match("ROTASI%-GO|[^|]*|(%d+)"))
                if tsGO and tsGO > 1e12 then tsGO = math.floor(tsGO/1000) end   -- ms -> s
                local delayGO = tsGO and (os.time() - tsGO) or nil
                -- v9.245: extract SUMBER (field ke-5). star_seed kirim |SS, panel gak ada
                -- penanda (=PANEL). Biar di log ketauan stock kedeteksi dari MANA.
                local srcGO = isiTop:match("ROTASI%-GO|[^|]*|[^|]*|[^|]*|(%a+)")
                local srcLabel = (srcGO == "SS" and "STAR_SEED")
                              or (srcGO == "SELF" and "SELF-DETECT")
                              or "PANEL"
                if ROTASI_STATE == "idle" then
                    -- v9.204: DEDUP per-seed cooldown (270s) pakai waktu proses.
                    -- v9.230: TAMBAH dedup pakai ts ROTASI-GO. Bug 2x: ROTASI-GO ke-2
                    -- dikirim panel PAS rotasi ke-1 jalan (ts cuma 101s dari ke-1), tapi
                    -- baru diproses setelah rotasi ke-1 kelar (407s) -> cooldown waktu-proses
                    -- udah lewat -> keproses 2x. Cek ts: 101s < 290 -> STALE, SKIP. 290s = mepet
                    -- 1 siklus (300s): nutup SEMUA re-fire dalam siklus, restock baru (300s) lolos.
                    local nowT = os.time()
                    local tsStale = tsGO and ROTASI_GO_TS_SEED[seedGO]
                                    and (tsGO - ROTASI_GO_TS_SEED[seedGO]) < 290
                    if tsStale or (ROTASI_SEED_TS[seedGO] and (nowT - ROTASI_SEED_TS[seedGO]) < 290) then
                        warn(("[rotasi] SKIP '%s' -- dedup cegah 2x (ts-gap %ss, proses-gap %ss, batas 290)"):format(
                            seedGO,
                            (tsGO and ROTASI_GO_TS_SEED[seedGO]) and tostring(tsGO - ROTASI_GO_TS_SEED[seedGO]) or "-",
                            ROTASI_SEED_TS[seedGO] and tostring(nowT - ROTASI_SEED_TS[seedGO]) or "-"))
                    else
                        ROTASI_SEED_TS[seedGO] = nowT
                        if tsGO then ROTASI_GO_TS_SEED[seedGO] = tsGO end
                        warn(("[rotasi] >>> STOCK dari %s: %s <<< rotasi%s%s"):format(
                            srcLabel,
                            seedGO,
                            placeGO and (" (dunia "..placeGO..")") or "",
                            delayGO and ((" [delay %ds dari %s kirim]"):format(delayGO, srcLabel)) or ""))
                        tambahLog(("Rotasi: stock dari %s -> %s"):format(srcLabel, seedGO))
                        pcall(function() jalankan_rotasi(cfg, seedGO, mapLink, placeGO) end)
                    end
                else
                    warn(("[rotasi] stock panel (%s) tapi rotasi lagi jalan -> skip"):format(seedGO))
                end
            end
            -- v9.246: STOCK LOKAL dari STAR_SEED -- star_seed di device SAMA nulis
            -- velium_stock.txt (baca game langsung, 0 delay API). Worker baca file lokal
            -- (0 backend, 0 tim, instant). Filter pakai rotasi_barang, dedup 290s.
            -- v9.247: WINDOW -- restock SELALU di kelipatan 5 menit (unix % 300 == 0).
            -- Worker CEK cuma 20 detik abis boundary (unix % 300 < 20). Selain itu SKIP
            -- (hemat, gak spam). Ini PRIORITAS: dicek di atas (sebelum denyut/open),
            -- cuma kalah sama lisensi/bypass (skipKarenaLisensi).
            if not skipKarenaLisensi and ROTASI_STATE == "idle" and cfg.rotasi_on
               and (os.time() % 300) < 20 then
                local rawSL = sh("su -c 'cat /sdcard/Delta/Workspace/velium_stock.txt 2>/dev/null'") or ""
                rawSL = rawSL:gsub("%s+$", "")
                if rawSL ~= "" and rawSL ~= STOCK_LOKAL_LAST then
                    STOCK_LOKAL_LAST = rawSL
                    local seedsSL, tsSL, placeSL = rawSL:match("^([^|]*)|(%d+)|(%d*)")
                    local tsLok = tonumber(tsSL)
                    if tsLok and (os.time() - tsLok) < 30 and seedsSL then   -- fresh (<30s)
                        local barangL = cfg.rotasi_barang and cfg.rotasi_barang:lower() or ""
                        for seed in seedsSL:gmatch("[^,]+") do
                            if barangL ~= "" and (","..barangL..","):find(","..seed:lower()..",", 1, true) then
                                local nowL = os.time()
                                if not (ROTASI_SEED_TS[seed] and (nowL - ROTASI_SEED_TS[seed]) < 290) then
                                    ROTASI_SEED_TS[seed] = nowL
                                    ROTASI_GO_TS_SEED[seed] = nowL
                                    local placeL = (placeSL and placeSL ~= "") and placeSL or nil
                                    if not placeL and cfg.rotasi_peta then
                                        for sN, pN in cfg.rotasi_peta:gmatch("([^,:]+):(%d+)") do
                                            if sN == seed then placeL = pN; break end
                                        end
                                    end
                                    local delayL = tsLok and (os.time() - tsLok) or nil
                                    warn(("[rotasi] >>> STOCK dari STAR_SEED (file lokal): %s <<<%s%s"):format(
                                        seed,
                                        placeL and (" (dunia "..placeL..")") or "",
                                        delayL and ((" [delay %ds]"):format(delayL)) or ""))
                                    tambahLog(("Rotasi: stock dari star_seed lokal -> %s"):format(seed))
                                    pcall(function() jalankan_rotasi(cfg, seed, mapLink, placeL) end)
                                    break   -- 1 rotasi per putaran
                                end
                            end
                        end
                    end
                end
            end
            -- v9.113: ROTASI TIM. Kalau rotasi_on + idle + cooldown lewat -> cek API
            -- stock tiap 8s. Ada barang keinginan -> jalankan sequence rotasi.
            -- v9.116: GATE KESIAPAN. Rotasi cuma boleh kalau tim 1 (1-10) LENGKAP
            -- nembak server (proses idup) + 1 menit. Biar pas awal start, stock yg
            -- lagi ada GAK langsung motong tim 1 yg belum kebentuk.
            -- v9.124: SELALU poll stock (catat baseline nextBoundary) tiap 8s SELAMA
            -- rotasi_on -- gak nunggu gate. Dulu poll cuma pas gate siap -> restock
            -- PERTAMA abis gate siap kelewat (cuma jadi baseline) -> nunggu 1 siklus
            -- (~5 menit) baru trigger. Sekarang baseline selalu fresh -> begitu gate
            -- siap, restock berikutnya langsung ke-trigger (gak kelewat).
            if cfg.rotasi_on and (os.time() - ROTASI_CEK_TS) >= 1 then
                ROTASI_CEK_TS = os.time()
                -- 1) SELALU poll (update ROTASI_NB_LAST) -> baseline gak pernah basi
                local barang = cek_stock_rotasi(cfg)
                -- 2) update gate kesiapan tim 1
                local tim1 = pkgs_slot(cfg, 1, TIM1_AKHIR)
                local idup = 0
                for _, pkg in ipairs(tim1) do if cacheHidup[pkg] then idup = idup + 1 end end
                if #tim1 > 0 and idup >= #tim1 then
                    if ROTASI_SIAP_TS == 0 then
                        ROTASI_SIAP_TS = os.time()
                        info("[rotasi] tim 1 lengkap nembak server -> tunggu 15s baru rotasi aktif (GACOR)")
                    end
                end
                local siap = ROTASI_SIAP_TS > 0 and (os.time() - ROTASI_SIAP_TS) >= 15
                -- v9.235: STOCK = PRIORITAS MUTLAK. Buang gate `siap` + cooldown antar
                -- rotasi (ROTASI_TS). Begitu stock kedeteksi + gak lagi rotasi -> LANGSUNG
                -- rotasi, gak nunggu tim 1 siap / gak nunggu jeda. User cuma mau 1 rotasi
                -- utama tiap stock -> dijamin dedup per-seed (ROTASI_SEED_TS 290s) di bawah.
                if barang and ROTASI_STATE == "idle" then
                    -- v9.222: cek cooldown PER-SEED (ROTASI_SEED_TS) -- biar self-detect
                    -- GAK dobel sama panel. Panel (v223+) udah detect + kirim ROTASI-GO,
                    -- top-loop set ROTASI_SEED_TS. Kalau seed ini baru dirotasi < 270s
                    -- (dari panel ATAU self-detect) -> SKIP. Nutup stock 2x.
                    local nowSD = os.time()
                    if ROTASI_SEED_TS[barang] and (nowSD - ROTASI_SEED_TS[barang]) < 290 then
                        info(("[rotasi] SKIP self-detect '%s' -- baru dirotasi %ds lalu (dedup sama panel, cegah 2x)"):format(
                            barang, nowSD - ROTASI_SEED_TS[barang]))
                    else
                        ROTASI_SEED_TS[barang] = nowSD
                        -- v9.232: JUGA set ROTASI_GO_TS_SEED (ts) -- biar ROTASI-GO panel
                        -- yg nyusul ke-dedup by TS (bukan waktu proses). Rotasi lama (~7
                        -- menit) bikin cooldown waktu-proses expired -> 2x. tsStale pakai
                        -- ini: panel-ts - self-ts < 290 -> SKIP. Self-detect + panel = 1x.
                        ROTASI_GO_TS_SEED[barang] = nowSD
                        -- v9.197: cari dunia SEED dari peta (self-detect tau dunia).
                        local placeR = nil
                        if cfg.rotasi_peta and barang and barang ~= "" then
                            for s, p in cfg.rotasi_peta:gmatch("([^,:]+):(%d+)") do
                                if s == barang then placeR = p; break end
                            end
                        end
                        -- v9.245: penanda sumber -> worker deteksi sendiri (bukan panel/star_seed)
                        warn(("[rotasi] >>> STOCK dari SELF-DETECT: %s <<< (worker poll API sendiri)"):format(barang))
                        tambahLog(("Rotasi: stock dari self-detect -> %s"):format(barang))
                        pcall(function() jalankan_rotasi(cfg, barang, mapLink, placeR) end)
                    end
                elseif barang and not siap then
                    info(("[rotasi] stock '%s' kedeteksi tapi tim 1 belum siap -> baseline dicatat, nunggu siap"):format(barang))
                end
            end

            -- v9.109: PUSH LOG ke panel tiap 60 detik (dijamin log RF lengkap sampai
            -- panel tiap menit walau gak ada event). wlog (LOG_KIRIM = semua log) ikut.
            if os.time() - LOG_PUSH_TS >= 60 then
                LOG_PUSH_TS = os.time()
                pcall(function() lapor(cfg, isiTop, cacheRun) end)
            end
            -- v9.40: log SIAPA yg kirim perintah (versi panel + IP dari backend).
            -- Buat lacak restart tiba-tiba -> ketauan dari panel versi berapa / IP mana.
            local pengirimTop = ambil_str(respTop, "pengirim") or ""
            -- v9.23: RESTART PRIORITAS. Bug user: pencet Start (RESTART) tapi worker
            -- lagi rejoin denyut 1-1 (10 client x 30s = lama) -> RESTART antri di
            -- belakang, grid 2x telat/gak jalan. Fix: kalau ada RESTART baru (beda
            -- dari lastIsi), SKIP rejoin denyut iterasi ini -> command handler di
            -- bawah langsung proses RESTART (tutup + grid 2x + buka fresh).
            -- v9.78 FIX LOOP: cek ts juga. RESTART yg ts-nya UDAH diproses
            -- (== RESTART_TS_PROSES) -> JANGAN skip rejoin denyut. Bug: RESTART
            -- netep di DB (ts sama, udah diproses) -> isiTop~=lastIsi true terus ->
            -- skip rejoin SELAMANYA -> client gak pernah dibuka (0/6 di game loop).
            local tsTop = ambil_num(respTop, "ts") or 0
            local restartBaru = (tsTop ~= (RESTART_TS_PROSES or 0))
            if (isiTop:upper():find("RESTART") or isiTop:upper():find("PAKSA"))
               and isiTop ~= lastIsi and restartBaru then
                info((isiTop:upper():find("PAKSA")
                    and "START PAKSA kedeteksi (dari: %s) -- langsung proses"
                    or "RESTART kedeteksi (dari: %s) -- skip rejoin denyut, langsung proses"):format(
                    pengirimTop ~= "" and pengirimTop or "?"))
                lewatiDenyutRejoin = true
            else
                lewatiDenyutRejoin = false
            end
            -- v9.34: CEK SETTING BERUBAH di TOP loop juga (ringan, cuma ts). User:
            -- start dari panel config kolom baru pas worker LAGI SIBUK (buka client/
            -- rejoin) -> setting telat kebaca (dicek jauh di bawah). Fix: kalau ts
            -- setting beda dari baseline -> paksa lewatiDenyutRejoin=true biar skip
            -- kerjaan iterasi ini, langsung nyampe handler setting di bawah.
            do
                local rSTop = api_get(cfg, "/setting-tim?tim=" .. cfg.tim)
                local tsSTop = ambil_num(rSTop, "ts") or 0
                if tsSTop > 0 and tsSTop ~= (SETTING_TS_TERAKHIR or 0) then
                    info("SETTING PANEL berubah (ts baru) -- skip rejoin, langsung proses setting")
                    lewatiDenyutRejoin = true
                    lastSettingCek = 0   -- paksa handler setting di bawah jalan iterasi ini
                end
            end
            -- v8.56: PROSES PLACE dari isiTop DI SINI (sebelum rejoin denyut). Bug:
            -- PLACE diproses jauh di bawah (setelah rejoin denyut) -> rejoin pakai
            -- place LAMA, PLACE fall baru kebaca 1-2 menit kemudian. Fix: cek PLACE
            -- di awal, update cfg.place_id SEBELUM rejoin -> rejoin langsung pakai
            -- place fall.
            do
                local placeTop = isiTop:match("PLACE:(%d+)")
                if placeTop and placeTop ~= cfg.place_id then
                    cfg.place_id = placeTop
                    pcall(function() save_config(cfg) end)
                    info("Place diganti ke " .. placeTop .. " (dari denyut-loop, sebelum rejoin)")
                    SUDAH_GRID = false; GRID_CACHE = nil
                    pcall(function() simpan_aktif(cfg) end)   -- v9.90: state ke-timpa (server baru)
                    -- v8.82: AUTO GETPS pas pindah ke place FALL (W2). User: sekali
                    -- pencet W2 PS -> otomatis get link dulu -> baru client jalan.
                    -- Jalanin `velium getps` (ambil accessCode per akun, simpen ke
                    -- backend) SEBELUM rejoin. Biar client masuk PS (bukan public).
                    -- Cuma buat place FALL (bukan W1 default), sekali per pindah.
                    if placeTop ~= "129343810645058" then
                        info("  AUTO GETPS -- ambil PS link semua akun dulu (biar gak public)...")
                        os.execute(((os.getenv("PREFIX") or "/data/data/com.termux/files/usr")
                            .. "/bin/velium") .. " getps")
                        pcall(refresh_ps_getps)   -- muat ulang ps_link yg baru ke-ambil
                    end
                end
                -- v8.64: proses GRID juga di denyut loop (bareng PLACE). Biar grid
                -- keset walau PLACE+GRID berebut cepet dari panel (Start flow). Cuma
                -- SET grid_kolom (gak tutup/buka client -- itu urusan blok utama).
                local gridTop = isiTop:match("GRID:(%w+)")
                if gridTop then
                    local kG = tonumber(gridTop)
                    local baru = (kG and kG >= 1) and kG or 0
                    if baru ~= (tonumber(cfg.grid_kolom) or 0) then
                        cfg.grid_kolom = baru
                        pcall(function() save_config(cfg) end)
                        -- v8.71: log CUKUP kolom yang diset (jangan grid_hitung -- dia
                        -- ngitung buat SEMUA client & bisa nampilin baris yang bikin
                        -- bingung sebelum client dibuka). Detail ukuran pas GRID nata.
                        info("Grid diset " .. (baru > 0 and (baru .. " kolom") or "otomatis") .. " (dari denyut-loop, kepakai pas nata)")
                        SUDAH_GRID = false; GRID_CACHE = nil
                        pcall(function() simpan_aktif(cfg) end)   -- v9.90: state ke-timpa (grid baru)
                    end
                end
            end
            local hitTop = isiTop:upper():find("FORCE") or isiTop:upper():find("REJOIN") or isiTop:upper():find("RESTART")
            -- v9.56: kalau perintah DB = FORCE/RESTART (hitTop), berarti UDAH START
            -- (config keset). Set MODE_JALAN=true. Bug user: worker re-exec (up) ->
            -- MODE_JALAN reset false, tapi perintah DB masih FORCE -> lisensi hilang
            -- dianggap "belum start" -> bypass ketunda. Infer dari perintah aktif.
            if hitTop then MODE_JALAN = true end
            -- v9.84: PULIHIN PKGS_AKTIF ABIS REBOOT. Bug user: RF reboot -> worker
            -- fresh -> PKGS_AKTIF=nil (gak persist), perintah DB=FORCE polos ->
            -- setAkun nil -> buka SEMUA (10) padahal cuma 6 dipilih. Grid ikut 10
            -- (petak beda ukuran, campur sama prefs lama 6). Fix: kalau FORCE aktif
            -- + PKGS_AKTIF belum ada -> baca /start-pilih (client dicentang panel),
            -- fallback ke client yg ADA AKUN (mapAkun). Sekali per boot (flag).
            if hitTop and (not PKGS_AKTIF or #PKGS_AKTIF == 0) and not PKGS_AKTIF_PULIH then
                local pilihArr = {}
                local rP = api_get(cfg, "/start-pilih?tim=" .. cfg.tim)
                local arrIsi = tostring(rP or ""):match('"pilih"%s*:%s*%[(.-)%]')
                if arrIsi and arrIsi ~= "" then
                    local setNm = {}
                    for nm in arrIsi:gmatch('"([^"]+)"') do setNm[nm] = true end
                    for _, pkg in ipairs(split(cfg.pkgs)) do
                        local u = (mapAkun or {})[pkg]
                        local nm = pkg:gsub("com%.roblox%.", "")
                        -- v9.122: rotasi_on -> pulihin cuma tim 1
                        if ((u and setNm[u]) or setNm[nm] or setNm[pkg]) and not rotasi_lewat(cfg, pkg) then pilihArr[#pilihArr+1] = pkg end
                    end
                end
                -- fallback: client yg ADA AKUN (kalau start-pilih kosong)
                if #pilihArr == 0 and mapAkun then
                    for _, pkg in ipairs(split(cfg.pkgs)) do
                        local u = mapAkun[pkg]
                        -- v9.122: rotasi_on -> cuma tim 1
                        if u and tostring(u) ~= "" and not rotasi_lewat(cfg, pkg) then pilihArr[#pilihArr+1] = pkg end
                    end
                end
                if #pilihArr > 0 and #pilihArr < #split(cfg.pkgs) then
                    PKGS_AKTIF = pilihArr
                    GRID_CACHE = nil
                    PKGS_AKTIF_PULIH = true   -- BERHASIL -> jangan ulang
                    info(("[boot] pulihin %d client aktif (dari %d config) -> grid + buka cuma ini"):format(
                        #pilihArr, #split(cfg.pkgs)))
                else
                    -- data belum siap (mapAkun/start-pilih kosong) -> JANGAN set flag,
                    -- retry ronde depan. Kalau emang semua client aktif (pilih=total),
                    -- gak masalah biarin nil.
                    if #pilihArr >= #split(cfg.pkgs) then
                        PKGS_AKTIF_PULIH = true   -- emang semua aktif, gak usah retry
                    end
                    info("[boot] start-pilih/akun belum nyaring (data belum siap / semua aktif) -- coba lagi nanti")
                end
            end
            -- v8.47: CEK denyut tiap 30s (bukan 2 menit). Ambang mati tetap 2 menit
            -- (120s). Bedanya: begitu denyut LEWAT 2 menit, cek berikutnya (max 30s
            -- lagi) LANGSUNG rejoin -- gak nunggu siklus cek 2 menit (yg bikin telat
            -- jadi ~4 menit). Baca denyut murah (file lokal 1 su call), jadi cek
            -- sering gak boros.
            -- v9.219: TAMBAH `or cfg.rotasi_on`. Bug: pas rotasi_on, /perintah sering
            -- ROTASI-GO (bukan FORCE) -> hitTop=false -> blok denyut SKIP -> DENYUT_UMUR
            -- kosong -> panel bilang OFF walau client jalan + nulis denyut. Sekarang
            -- rotasi_on JUGA jalanin blok denyut (rejoin/lapor tim 1).
            -- v9.220: TAPI kalau lagi ADA STOCK (rotasi JALAN, ROTASI_STATE != idle) ->
            -- SKIP denyut. User: pas ada stock, borong DIUTAMAIN, jangan ngurus denyut.
            -- (tim 1 juga lagi ditutup pas rotasi, jadi emang gak perlu diurus.)
            if (hitTop or cfg.rotasi_on) and ROTASI_STATE == "idle" and (os.time() - (KICK_DIURUS["_denyutTop"] or 0)) >= 30 then
                KICK_DIURUS["_denyutTop"] = os.time()
                local pkgList = split(cfg.pkgs or "")
                -- v8.34: kalau FORCE:daftar-akun -> cuma hitung akun ITU (bukan
                -- semua 10). Parse daftar, cocokin sama mapAkun (pkg->username).
                local daftarForce = isiTop:match("FORCE:([%w%.%_,]+)") or isiTop:match("RESTART:([%w%.%_,]+)")
                local setAkun = nil
                if cfg.rotasi_on then
                    -- v9.120: ROTASI nyala -> denyut/rejoin CUMA tim 1 (10 pkg pertama),
                    -- LANGSUNG dari cfg.pkgs (gak ngandelin PKGS_AKTIF yg bisa ke-reset).
                    -- Tanpa ini, denyut ngurus 19 (rejoin tim 2 yg harusnya standby).
                    setAkun = {}
                    for i = 1, math.min(TIM1_AKHIR, #pkgList) do
                        local pkg = pkgList[i]
                        setAkun[pkg] = true
                        local u = mapAkun and mapAkun[pkg]
                        if u then setAkun[u] = true end
                    end
                elseif daftarForce then
                    setAkun = {}
                    for a in daftarForce:gmatch("[^,]+") do setAkun[a] = true end
                elseif PKGS_AKTIF and #PKGS_AKTIF > 0 then
                    -- v9.47: FORCE polos tapi PKGS_AKTIF ada (jalan 6) -> filter pakai
                    -- PKGS_AKTIF (pkg-based). Bug: FORCE polos pas jalan 6 -> antrian
                    -- cek/rejoin 10. Sekarang cuma client aktif yg dicek.
                    setAkun = {}
                    for _, pkg in ipairs(PKGS_AKTIF) do
                        setAkun[pkg] = true
                        local u = mapAkun and mapAkun[pkg]
                        if u then setAkun[u] = true end
                    end
                end
                -- v9.90: JANGAN PERNAH buka SEMUA (daftar polos). Kalau sampai sini
                -- setAkun masih nil (FORCE polos + PKGS_AKTIF kosong) -> pakai client
                -- yg ADA AKUN (mapAkun) sebagai daftar. User: harus SELALU ada daftar
                -- dulu, gak pernah polos. Cuma kalau BENER2 gak ada akun -> biarin nil
                -- (gak ada yg dibuka, bukan buka semua kosong).
                if not setAkun and mapAkun then
                    local s, ada = {}, 0
                    for _, pkg in ipairs(split(cfg.pkgs)) do
                        local u = mapAkun[pkg]
                        if u and tostring(u) ~= "" then s[pkg] = true; s[u] = true; ada = ada + 1 end
                    end
                    if ada > 0 then
                        setAkun = s
                        info(("[daftar] FORCE polos -> pakai %d client yg ADA AKUN (gak buka semua)"):format(ada))
                    end
                end
                -- v8.88: SET client aktif buat grid LANGSUNG dari perintah panel.
                -- Panel udah kasih tau 6 client mana (FORCE:daftar) -> grid dihitung
                -- buat 6 itu (3 kolom = 3x2), bukan semua 10 (yg bikin 4x3).
                -- FORCE polos (tanpa daftar) = semua client.
                do
                    local aktifBaru = nil
                    if setAkun then
                        -- v9.15: URUTAN CONFIG (split cfg.pkgs), bukan pairs(mapAkun)
                        -- yg ACAK -> grid mulai kiri-atas urut, gak acak.
                        aktifBaru = {}
                        for _, pkg in ipairs(split(cfg.pkgs)) do
                            local u = (mapAkun or {})[pkg]
                            local nm = pkg:gsub("com%.roblox%.", "")
                            if setAkun[u] or setAkun[pkg] or setAkun[nm] then
                                aktifBaru[#aktifBaru+1] = pkg
                            end
                        end
                        if #aktifBaru == 0 then aktifBaru = nil end
                    end
                    -- kalau berubah -> reset cache grid
                    local sigBaru = aktifBaru and (#aktifBaru) or 0
                    if (PKGS_AKTIF and #PKGS_AKTIF or 0) ~= sigBaru then
                        GRID_CACHE = nil
                    end
                    PKGS_AKTIF = aktifBaru
                    if PKGS_AKTIF and #PKGS_AKTIF > 0 then simpan_aktif(cfg) end   -- v9.89: simpen state
                end
                -- v8.44: grafis_semua DIBUANG (gak dipake lagi -- deteksi udah
                -- pindah ke DENYUT doang). Dulu ambil grafis semua client (mahal,
                -- su call per client) tapi hasilnya gak kepake. Hemat.
                -- v8.37: cek DENYUT FILE lokal (0 request CF). Script star_seed
                -- v3.79 nulis /sdcard/Delta/Workspace/velium_denyut_<akun>.txt tiap
                -- 20s selama BENERAN di game (disconnect = script mati = file gak
                -- ke-update). Logcat gak reliable (buffer log lama). File lokal =
                -- akurat: grafis TINGGI tapi denyut MATI (>2 menit) = disconnect.
                -- Baca SEMUA file denyut sekali (1 su call, gak makan CF).
                local denyutSemua = {}   -- akun -> umur denyut (detik), nil kalau gak ada
                do
                    local sekarang = os.time()
                    -- baca isi (timestamp) + MTIME file (kapan file terakhir ditulis).
                    -- format: nama|isi_timestamp|mtime_epoch
                    local raw = sh("su -c 'cd \"" .. cfg.workspace_dir .. "\" 2>/dev/null && for f in velium_denyut_*.txt; do [ -f \"$f\" ] && echo \"$f|$(cat \"$f\" 2>/dev/null)|$(stat -c %Y \"$f\" 2>/dev/null)\"; done' 2>/dev/null") or ""
                    local ddetail = {}
                    local sheckDenyut = {}   -- v9.254: sheckles dari denyut file (nebeng)
                    for line in raw:gmatch("[^\n]+") do
                        -- v9.254: isi denyut skrg "ts;sheck;sheckW" (dulu cuma ts). Match
                        -- isi sbg [^|]* (bukan %d+), extract ts + sheckles dari situ.
                        local nama, isi, mtime = line:match("velium_denyut_(.-)%.txt|([^|]*)|(%d+)")
                        local ts = isi and isi:match("^(%d+)")
                        if nama and ts then
                            local umurIsi = sekarang - tonumber(ts)      -- dari timestamp DALAM file
                            local umurMtime = mtime and (sekarang - tonumber(mtime)) or nil  -- dari mtime file
                            denyutSemua[nama] = umurIsi
                            -- v9.254: extract sheckles (ts;sheck;sheckW). sheck>0 aja.
                            -- format egg2 (ts;gemEgg;chrEgg;egg2) -> pisah gem + christmas egg
                            if isi:match("^%d+;%d+;%d+;egg2$") then
                                local gem, chr = isi:match("^%d+;(%d+);(%d+);egg2")
                                if (tonumber(gem) or 0) > 0 or (tonumber(chr) or 0) > 0 then
                                    sheckDenyut[#sheckDenyut+1] = { nama = nama, sheck = gem or "0", sheckW = "egg", chr = chr or "0" }
                                end
                            else
                                local sk, sw = isi:match("^%d+;(%d+);(%a*)")
                                if sk and (tonumber(sk) or 0) > 0 then
                                    sheckDenyut[#sheckDenyut+1] = { nama = nama, sheck = sk, sheckW = sw or "" }
                                end
                            end
                            if #ddetail < 6 then
                                ddetail[#ddetail+1] = ("%s(isi=%ds mtime=%ss)"):format(
                                    nama, umurIsi, umurMtime and tostring(umurMtime) or "?")
                            end
                        end
                    end
                    -- v9.254: kirim sheckles SEMUA akun sekaligus ke panel (nebeng denyut,
                    -- 1 request). Gak ilang walau akun mati (file lokal tetep ada).
                    if #sheckDenyut > 0 then
                        local body = '{"akun":['
                        for i, d in ipairs(sheckDenyut) do
                            body = body .. '{"akun":"' .. d.nama .. '","sheck":' .. d.sheck ..
                                   ',"sheckW":"' .. d.sheckW .. '"' ..
                                   (d.chr and (',"chr":' .. d.chr) or '') .. '}'
                            if i < #sheckDenyut then body = body .. "," end
                        end
                        body = body .. "]}"
                        pcall(function() api_post(cfg, "/stat-batch", body) end)
                    end
                    local dcnt = 0
                    for _ in pairs(denyutSemua) do dcnt = dcnt + 1 end
                    DENYUT_UMUR = denyutSemua   -- v9.77: simpen global biar lapor kirim ke panel
                    if dcnt > 0 then
                        info(("[denyut] jam_device=%s | %d file: %s"):format(
                            os.date("%H:%M:%S"), dcnt, table.concat(ddetail, " ")))
                    else
                        info("[denyut] 0 file denyut kebaca (script belum nulis / path beda?)")
                    end
                end
                -- v9.177: FIX TIMING. Panel kirim START PAKSA -> FORCE -> ROTASI
                -- (urutan). Antrian ini JALAN pas FORCE round (START PAKSA), SEBELUM
                -- ROTASI kedispatch -> rotasi_on masih FALSE -> semua 20 kebuka
                -- (v9.175/176 gak ngefek). Fix: RE-CEK /perintah -- kalau ROTASI udah
                -- masuk (on), set rotasi_on SEKARANG biar antrian skip Tim 2.
                do
                    local pR = ambil_str(api_get(cfg, "/perintah?tim=" .. cfg.tim), "isi") or ""
                    local uR = pR:upper()
                    if uR:find("ROTASI") and not uR:find("ROTASI%-") then
                        local isiRot = (pR:match("ROTASI:(.*)$") or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if isiRot ~= "" and isiRot:lower() ~= "off" and not cfg.rotasi_on then
                            cfg.rotasi_on = true
                            cfg.rotasi_barang = isiRot:match("^(.-)|") or isiRot
                            ROT_TIM1 = nil   -- reset cache tim1 biar dihitung ulang
                            info("[antrian] ROTASI kedeteksi di /perintah -> rotasi_on=true (Tim 2 STANDBY)")
                        end
                    end
                end
                local perlu, diGame = 0, 0
                local perluTembak = {}   -- v8.34: client OUT yg mau di-rejoin
                for _, pkg in ipairs(pkgList) do
                    local ak = mapAkun and mapAkun[pkg]
                    -- skip cookie mati + (kalau FORCE:daftar) skip yg bukan di daftar
                    -- v9.47: cek akun ATAU pkg (PKGS_AKTIF pkg-based, FORCE:daftar akun-based)
                    local diForce = (not setAkun) or (ak and setAkun[ak]) or setAkun[pkg]
                    -- v9.175: pas ROTASI ON, SKIP Tim 2 (client 11-20) di antrian.
                    -- User: rotasi = Tim 1 (1-10) loop utama, Tim 2 (11-20) STANDBY
                    -- (cuma kebuka pas ada stock via buka_grup_rotasi). Dulu antrian
                    -- gak cek rotasi -> semua 20 kebuka. rotasi_lewat=true buat Tim 2.
                    if diForce and not (ak and KICK_DIURUS["mati:" .. ak]) and not rotasi_lewat(cfg, pkg) then
                        perlu = perlu + 1
                        -- v8.43: DETEKSI PAKAI DENYUT DOANG (buang cek grafis game).
                        -- User: rejoin cek dari denyut SD card. Kalau 2 menit gak
                        -- ngirim denyut = client WAJIB rejoin. Grafis RAM gak dipake
                        -- lagi (gak bisa bedain di-game vs layar disconnect).
                        local umur = ak and denyutSemua[ak]
                        if ak then
                            info(("[denyut-cek] %s: umur=%s")
                                :format(ak, umur and (umur.."s") or "BELUM ADA FILE"))
                        end
                        if umur ~= nil and umur <= 180 then
                            -- v9.276: toleransi denyut 120 -> 180s (3 menit). denyut fresh
                            -- (<=3 menit) = script nulis = DI GAME. Dilonggarin biar transisi
                            -- market<->garden (place beda, ada jeda denyut pas teleport) gak
                            -- ke-rejoin sia-sia. denyut ditulis tiap 20s -> masih banyak margin.
                            diGame = diGame + 1
                            -- v8.47: denyut fresh = client masuk game = CAPTCHA SOLVED.
                            -- Clear flag captcha (dulu clear di loop grafis lama yg
                            -- OFF -> captcha stuck selamanya). Sekarang clear di sini.
                            if KICK_DIURUS["captcha:" .. pkg] then
                                info(("[antrian] %s CAPTCHA kelar (denyut fresh = masuk game)")
                                    :format(ak or pkg))
                                KICK_DIURUS["captcha:" .. pkg] = nil
                            end
                        elseif umur == nil then
                            -- belum ada file denyut. BEDAIN 2 kasus (v9.42):
                            -- (a) proses HIDUP = client baru dibuka, script belum
                            --     sempet nulis denyut (~20s) -> toleransi, anggap di
                            --     game, JANGAN rejoin (nunggu denyut nyusul).
                            -- (b) proses MATI = client BELUM PERNAH dibuka (Start
                            --     pertama, semua mati) -> WAJIB REJOIN (buka!).
                            -- Bug user: Start gak pernah mulai -- dulu SEMUA umur==nil
                            -- dianggap di game -> 6/6 -> worker gak buka client sama
                            -- sekali. Sekarang cek cacheHidup: mati = buka.
                            if cacheHidup[pkg] then
                                diGame = diGame + 1   -- proses hidup, denyut nyusul
                            elseif KICK_DIURUS["tembak_ts:" .. pkg] and (os.time() - KICK_DIURUS["tembak_ts:" .. pkg]) < 240 then
                                -- v9.296: baru di-CLOSE/tembak (grace) -> JANGAN buka walau
                                -- belum ada file denyut. FORCE dari panel yg buka. Cegah
                                -- double-open pas boot (denyut-rejoin buka duluan, terus
                                -- FORCE buka lagi). Dulu grace cuma dicek di cabang "denyut
                                -- basi", gak di "belum ada file" -> boot tetep dobel.
                                diGame = diGame + 1
                                info(("[antrian] %s belum ada denyut TAPI baru di-close/tembak %ds lalu -> GRACE (tunggu FORCE)")
                                    :format(ak or pkg, os.time() - KICK_DIURUS["tembak_ts:" .. pkg]))
                            else
                                perluTembak[#perluTembak+1] = pkg   -- proses mati = buka
                                info(("[antrian] %s proses MATI + belum ada denyut = WAJIB BUKA")
                                    :format(ak or pkg))
                            end
                        else
                            -- umur > 120s = denyut MATI >2 menit.
                            -- v9.221: GRACE -- kalau client BARU DIBUKA (< 180s lalu),
                            -- JANGAN rejoin walau denyut basi (grace 240s = 4 menit, krn masuk PS ~3 menit). Dia masih loading/spawn
                            -- (belum sempet nulis denyut fresh ~2 menit). Rejoin di sini =
                            -- INTERRUPT loading -> client nyangkut di HOME -> loop terus.
                            if KICK_DIURUS["tembak_ts:" .. pkg] and (os.time() - KICK_DIURUS["tembak_ts:" .. pkg]) < 240 then
                                diGame = diGame + 1   -- anggap di game (lagi loading), tunggu denyut nyusul
                                info(("[antrian] %s baru dibuka %ds lalu -> GRACE (loading, JANGAN rejoin)")
                                    :format(ak or pkg, os.time() - KICK_DIURUS["tembak_ts:" .. pkg]))
                            elseif KICK_DIURUS["captcha:" .. pkg] then
                                -- v8.70: RE-CEK pakai logcat doang. Logcat masih ada
                                -- captcha fresh (<120s) -> masih captcha. Kalau udah
                                -- bersih -> udah solved / false positive -> lepas + rejoin.
                                if cek_captcha_logcat(pkg) then
                                    info(("[antrian] %s CAPTCHA (logcat masih fresh, skip rejoin, solve manual)")
                                        :format(ak or pkg))
                                else
                                    KICK_DIURUS["captcha:" .. pkg] = nil
                                    perluTembak[#perluTembak+1] = pkg
                                    info(("[antrian] %s captcha udah kelar (logcat bersih) = REJOIN"):format(ak or pkg))
                                end
                            else
                                local isCap, nWeb = cek_captcha_webview(pkg)
                                -- v8.70: CUMA logcat (uiautomator dibuang -- berat +
                                -- ganggu client lain). Captcha = logcat ada arkose.
                                -- fd webview tinggi TAPI logcat bersih = false positive
                                -- -> REJOIN normal (bukan skip).
                                local capLog = cek_captcha_logcat(pkg)
                                if capLog then
                                    if ak then KICK_DIURUS["captcha:" .. pkg] = ak end
                                    info(("[antrian] %s CAPTCHA (logcat arkose, webview %d fd) -> skip rejoin, solve manual")
                                        :format(ak or pkg, nWeb or 0))
                                else
                                    perluTembak[#perluTembak+1] = pkg
                                    if isCap then
                                        info(("[antrian] %s denyut MATI (%ss) -- %d fd webview tapi logcat BERSIH (bukan captcha) = REJOIN")
                                            :format(ak or pkg, umur, nWeb or 0))
                                    else
                                        info(("[antrian] %s denyut MATI (%ss) = WAJIB REJOIN")
                                            :format(ak or pkg, umur))
                                    end
                                end
                            end
                        end
                    end
                end
                info(("[antrian] %d/%d di game (%d perlu diurus)"):format(diGame, perlu, perlu - diGame))
                tambahLog(("[antrian] %d/%d di game (%d perlu diurus)"):format(diGame, perlu, perlu - diGame))
                if #perluTembak > 0 and not lewatiDenyutRejoin then
                    -- v8.54: REFRESH mapLink (+ accessCode per akun) SEBELUM tembak.
                    -- Bug: blok denyut ini pakai mapLink dari refresh terakhir, kalau
                    -- accessCode di-set SETELAH itu (klik World 2 Private) -> mapLink
                    -- kosong -> join PUBLIC. Refresh di sini biar accessCode terbaru
                    -- kepakai -> join PS-access per akun.
                    pcall(refresh_ps); pcall(refresh_ps_getps)
                    -- v8.68 FIX: CEK LISENSI DULU sebelum rejoin. Bug user: rejoin
                    -- denyut buka client TANPA cek lisensi -> client kebuka nyangkut
                    -- di layar "Enter key" (lisensi hilang) -> baru ketahuan pas FORCE
                    -- di tengah sesi. Sekarang: lisensi hilang -> SKIP rejoin (jangan
                    -- buka client percuma). Bypass diurus pas FORCE/open_all (yg emang
                    -- buka 1 client buat ambil key dengan bener).
                    do
                        local kd = lisensi_keadaan(cfg)
                        if kd ~= "ada" then
                            perluTembak = {}   -- kosongin -> gak rejoin ronde ini
                            -- v9.55: paksa bypass CUMA kalau udah Start (MODE_JALAN).
                            -- Belum Start = config belum tau (grid) -> tunda. Antrian
                            -- ini umumnya cuma jalan pas udah Start, tapi eksplisit.
                            -- v9.238: gate 300s -> 60s. Bug user: lisensi hilang tapi
                            -- worker nunggu 5 MENIT tiap kali baru coba pulihin -> client
                            -- nyangkut layar key ~28 menit. Sekarang tiap 60s langsung
                            -- coba bypass pulihin lisensi (jangan nganggur "SKIP rejoin").
                            if MODE_JALAN and (os.time() - (BYPASS_TERAKHIR or 0)) > 60 then
                                warn(("[antrian] Lisensi Delta %s -- SKIP rejoin, PAKSA bypass pulihin lisensi (tiap 60s)..."):format(
                                    kd == "hilang" and "HILANG" or "BASI"))
                                lastLisensiCek = 0   -- paksa bypass ronde berikutnya (gak nunggu 10 menit)
                            else
                                warn(("[antrian] Lisensi Delta %s -- SKIP rejoin (client bakal nyangkut layar key)."):format(
                                    kd == "hilang" and "HILANG" or "BASI"))
                            end
                        end
                    end
                    if #perluTembak > 0 then
                    -- v9.128: ROTASI nyala -> tim 1 tembak BARENGAN pakai buka_grup_rotasi
                    -- (grid all + am start all, TANPA task-remove+sleep5 per client yg
                    -- bikin open_one lambat ~5s/client). 10 client buka detik-detikan.
                    if cfg.rotasi_on then
                        info(("[antrian] %d client OUT -> ROTASI: tembak BARENGAN (bukan 1-1)"):format(#perluTembak))
                        -- v9.225: rejoin bisa di-ABORT sama stock. cekAbort baca /perintah,
                        -- true kalau ada ROTASI-GO baru (stock) -> berhenti rejoin, top-loop
                        -- proses rotasi. User: baca perintah panel itu UTAMA.
                        pcall(function() buka_grup_rotasi(cfg, perluTembak, mapLink, 90, function()
                            local cekP = api_get(cfg, "/perintah?tim=" .. cfg.tim)
                            local isiP = ambil_str(cekP, "isi") or ""
                            return isiP:upper():find("ROTASI%-GO") ~= nil and isiP ~= ROTASI_GO_LAST
                        end) end)
                        -- v9.221: catat waktu buka tiap client -> GRACE 180s (jangan rejoin
                        -- < 240s abis dibuka (~3 menit masuk PS + margin), biar loading gak ke-interrupt = nyangkut home)
                        local tnowBuka = os.time()
                        for _, pkg in ipairs(perluTembak) do KICK_DIURUS["tembak_ts:" .. pkg] = tnowBuka end
                    else
                    info(("[antrian] %d client OUT -> rejoin (1-1 tiap 30s)"):format(#perluTembak))
                    for idx, pkg in ipairs(perluTembak) do
                        -- v9.68: cek perintah panel -> nyela. Loop rejoin jalan pas
                        -- FORCE, jadi PAKSA/RESTART/STANDBY/CLOSE baru = nyela.
                        -- isiLagiJalan="FORCE" biar PAKSA/RESTART ke-detect beda.
                        if (cek_batal and cek_batal()) or ada_perintah_baru(cfg, "FORCE") then break end
                        -- v8.65: TULIS GRID posisi SEBELUM buka client. Bug: blok
                        -- denyut buka client TANPA nulis prefs grid dulu -> posisi
                        -- window pakai default/lama (bukan 3x2 yg diset). grid_satu
                        -- nulis prefs posisi client ini (App Cloner baca pas buka).
                        pcall(function() grid_satu(cfg, pkg) end)
                        open_one(cfg, pkg, mapLink and mapLink[pkg] or nil, "grafis-out")
                        pcall(function() jaga_depan(cfg, mapLink) end)
                        -- v8.44: jeda 30s antar rejoin (tembak 1-1, bukan barengan).
                        -- User: kalau 5 client keluar, tembak 1-1 selama 30s. Client
                        -- terakhir gak perlu jeda.
                        if idx < #perluTembak then
                            for _ = 1, 30 do
                                -- v9.68: cek perintah panel tiap detik -> nyela cepet
                                if (cek_batal and cek_batal()) or ada_perintah_baru(cfg, "FORCE") then break end
                                os.execute("sleep 1")
                            end
                        end
                    end
                    end
                    end
                    end
            end
        end

        local resp = api_get(cfg, "/perintah?tim=" .. cfg.tim)
        local isi  = ambil_str(resp, "isi") or ""
        -- v6.84: kalau perintah KOSONG (worker baru jalan / panel belum set) ->
        -- STANDBY. User minta FORCE HARUS dari panel -- worker jalan itu STANDBY
        -- dulu (cek cookie/lisensi, GAK buka client), nunggu user pencet FORCE
        -- di panel. Dulu (v6.82) default FORCE -> worker langsung buka client
        -- sendiri, padahal user mau nunggu perintah panel.
        if isi == "" or isi == "-" then
            -- v9.44: kalau UDAH jalan (MODE_JALAN=true, udah pencet Start) -> perintah
            -- kosong = tetep FORCE (lanjut jalan). User: setelah Start gak boleh balik
            -- STANDBY sendiri. Cuma kalau BELUM start (MODE_JALAN false) -> STANDBY
            -- awal (nunggu Start). Cuma STOP dari panel yg matiin.
            if MODE_JALAN then
                isi = "FORCE"
            else
                isi = "STANDBY"
            end
        end
        -- v8.49: CEK STOP PRIORITAS (deteksi cepet + tutup barengan). STOP baru ->
        -- reset lastOpen + anggap sisa loop standby (gak buka client).
        if cek_stop_panel(cfg, isi) then
            lastOpen = 0
            isi = "STANDBY"
        end
        -- v6.29: LOGIN tertunda (kesimpen pas cek_batal) diproses DULUAN, biar
        -- gak keburu ketimpa FORCE. Ambil & bersihin penanda.
        if KICK_DIURUS["login_tertunda"] then
            isi = KICK_DIURUS["login_tertunda"]
            KICK_DIURUS["login_tertunda"] = nil
            info("LOGIN tertunda diproses: " .. isi)
        end

        -- v6.35: LOGIN DIPROSES PALING ATAS -- sebelum cek lisensi/beku/nyangkut.
        -- Dulu LOGIN handler ada di tengah loop, ketutup aktivitas lain (client
        -- beku, cek lisensi). Kalau ada client beku, worker sibuk situ, LOGIN
        -- gak kebagian giliran -> nyangkut. Sekarang LOGIN paling awal, langsung.
        local loginKelar = false
        if isi:match("^LOGIN:") then
            -- v6.45: ANTRE LOGIN. Backend bisa gabung banyak LOGIN pakai ";"
            -- (LOGIN:A:c1;LOGIN:B:c2;...) pas user spam ganti akun cepat. Proses
            -- SEMUA di antrean, satu-satu. Dulu cuma 1 yang kebaca (saling nimpa).
            -- v6.46: HAPUS antrean LOGIN dari backend DULU (ganti perintah biasa)
            -- sebelum diproses. Gitu tiap LOGIN diproses SEKALI, backend bersih.
            -- v7.09: ganti akun SELALU balik ke STANDBY. User minta: ganti akun
            -- itu operasi STANDBY -- gak boleh auto-lanjut FORCE. Dulu balikKe bisa
            -- "FORCE" kalau perintah sebelumnya FORCE (FORCE lama nyantol) -> habis
            -- ganti akun worker buka semua client + bypass lisensi tutup semua.
            -- Sekarang: ganti akun -> balik STANDBY. FORCE cuma jalan kalau user
            -- PENCET START sendiri (bukan warisan FORCE lama).
            -- v9.44: ganti akun -> balik ke mode SEKARANG. Kalau UDAH jalan
            -- (MODE_JALAN=true, udah Start) -> FORCE (lanjut jalan, gak berhenti).
            -- Kalau BELUM start (standby) -> STANDBY (gak buka client sendiri).
            -- User: setelah Start gak boleh balik STANDBY sendiri.
            -- v9.46: FORCE dgn DAFTAR client (dari PKGS_AKTIF) biar gak buka semua 10.
            local balikGanti
            if MODE_JALAN then
                -- v9.95: pakai force_str (FORCE:daftar dari PKGS_AKTIF) -- konsisten,
                -- gak pernah polos kalau ada daftar.
                balikGanti = force_str(cfg, mapAkun)
            else
                balikGanti = "STANDBY"
            end
            pcall(function()
                api_post(cfg, "/perintah", string.format('{"tim":%s,"isi":"%s"}', jstr(cfg.tim), balikGanti), "PUT")
            end)
            -- v6.47: dedup DALAM antrean ini aja (biar kalau backend kebetulan
            -- gabung 2x client sama, gak diproses dobel). GAK ada penanda
            -- permanen -- backend udah dibersihin (FORCE) di atas, jadi LOGIN
            -- yang sama bisa diulang LANGSUNG (suntik lagi = proses lagi), tanpa
            -- nunggu jeda / loop.
            local dproses = {}
            for satu in (isi .. ";"):gmatch("(.-);") do
                local akunG, clientG = satu:match("^LOGIN:([^:]+):([^:]+)")
                if akunG and clientG and not dproses[satu] then
                    dproses[satu] = true
                    local pkgG = clientG:find("%.") and clientG or ("com.roblox." .. clientG)
                    -- v6.83: baca akun LAMA (yang lagi kepasang di client ini)
                    -- SEBELUM suntik -> log jelas "akun lama -> akun baru".
                    local akunLama = baca_username(pkgG) or "?"
                    print("")
                    print(C.BOLD .. C.C .. ">>> GANTI AKUN <<<" .. C.N)
                    info(("Client %s: cookie %s -> %s"):format(
                        clientG, akunLama, akunG))
                    KICK_DIURUS["mati:" .. akunG] = nil
                    os.execute(("timeout 120 %s login %s %s"):format(
                        (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium",
                        akunG, pkgG:gsub("com%.roblox%.", "")))
                    -- v6.83: CEK akun baru kebaca di client (dari prefs.xml,
                    -- pakai baca_username yg udah ke-scope). Kalau username di
                    -- client udah = akun baru -> cookie kebaca, AMAN siap. Kalau
                    -- masih kosong/akun lama -> tunggu (prefs kadang telat ke-update).
                    os.execute("sleep 1")   -- kasih waktu prefs ke-tulis
                    local pkgPendVerif = pkgG:gsub("com%.roblox%.", "")
                    local unameBaru = baca_username(pkgG) or ""
                    -- v6.98: VERIFIKASI cookie SEBELUM buka client (pas fresh, belum
                    -- ke-timpa Roblox). Kalau username udah = akun target -> tandai
                    -- cookie_ok. Cek-ganti percaya tanda ini (gak baca ulang cookie
                    -- dari client yang bisa ke-overwrite pas dibuka). Dulu cek-ganti
                    -- baca cookie SETELAH client buka -> ke-timpa -> "gak kebaca".
                    if unameBaru ~= "" and unameBaru:lower() == akunG:lower() then
                        ok(("Cookie %s AMAN, siap (kebaca di client sebelum buka)"):format(akunG))
                    else
                        -- prefs belum keupdate -> cek langsung dari cookie yang disuntik
                        local dbV = "/data/data/" .. pkgG .. "/app_webview/Default/Cookies"
                        local hV = io.popen(("timeout 8 su -c %s 2>/dev/null"):format(shq(
                            "/data/data/com.termux/files/usr/bin/sqlite3 " .. dbV ..
                            " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
                        local ckV = hV and hV:read("*all") or ""
                        if hV then hV:close() end
                        ckV = cookie_terpanjang(ckV or "")
                        local unVck = (ckV ~= "" and ckV:find("_|WARNING")) and uname_dari_cookie(ckV) or ""
                        if unVck ~= "" and unVck:lower() == akunG:lower() then
                            ok(("Cookie %s AMAN, siap (kebaca dari cookie)"):format(akunG))
                        elseif unameBaru ~= "" then
                            info(("Client kebaca sbg %s (nunggu update ke %s)"):format(unameBaru, akunG))
                        else
                            info(("Cookie %s kesuntik -- kebaca pas masuk game"):format(akunG))
                        end
                    end
                    -- v6.69: LANGSUNG MASUK ULANG client abis suntik cookie (ke
                    -- public). Tanpa ini, cookie kesuntik TAPI client gak dibuka
                    -- -> akun baru gak aktif (diem), apalagi pas standby. GAK
                    -- di-kill (force-stop) -- cukup open_one (am start) buat masuk
                    -- ulang; lebih ringan & cepet, cookie baru langsung kepakai.
                    KICK_DIURUS["captcha:" .. pkgG] = nil   -- reset penanda captcha akun lama
                    -- v6.91: kalau lagi STANDBY, JANGAN buka client -- cukup suntik
                    -- cookie (persiapan). Client dibuka nanti pas user FORCE. Cek
                    -- perintah SEKARANG (isiSekarang) standby apa nggak.
                    local isiSekarang = ambil_str(api_get(cfg, "/perintah?tim=" .. cfg.tim), "isi") or ""
                    local lagiStandby = isiSekarang:upper():find("STANDBY") or isiSekarang:upper():find("STOP")
                    -- v9.176: pas ROTASI ON, Tim 2 (11-20) = STANDBY -> JANGAN buka via
                    -- ganti-akun juga. Cukup suntik cookie (persiapan), buka pas rotasi.
                    if lagiStandby or rotasi_lewat(cfg, pkgG) then
                        info("STANDBY/tim2-rotasi -- cookie disiapin, client DIBUKA pas FORCE/rotasi nanti.")
                    else
                        -- v7.02: GAK perlu suntik ulang (spam). Cookie udah masuk
                        -- bener (creation_utc wajar -> Roblox terima, gak dihapus).
                        info("Masuk ulang " .. clientG .. " dengan akun baru...")
                        open_one(cfg, pkgG, mapLink and mapLink[pkgG] or nil, "ganti-akun")
                        os.execute("sleep 3")
                    end
                    -- v6.48: SIMPEN TARGET akun per client + jadwal CEK 60 detik
                    -- ke depan. Nanti worker cek: client udah beneran ganti ke
                    -- akun ini? Kalau belum -> lapor alasan + auto re-suntik.
                    local pkgPend = pkgG:gsub("com%.roblox%.", "")
                    KICK_DIURUS["target:" .. pkgPend] = akunG
                    KICK_DIURUS["cekganti:" .. pkgPend] = os.time() + 60
                    KICK_DIURUS["retry:" .. pkgPend] = 0
                    KICK_DIURUS["tglganti:" .. pkgPend] = os.time()  -- v7.09: buat timeout
                    refresh_status(); lastStatusCek = os.time()
                    gambar_tabel(isi)
                end
            end
            lastIsi = isi
            loginKelar = true   -- skip sisa loop ronde ini
            -- v6.95: catat AKTIVITAS ganti akun. Loop biasa (buka client) nunggu
            -- 3 menit setelah ini -- biar ganti akun kelar + adem dulu, gak
            -- tabrakan sama farming.
            waktuAktivitas = os.time()
        end

        if not loginKelar then

        -- v4.16: refresh status (dumpsys, berat) cuma tiap 10 detik, bukan tiap redraw.
        if (os.time() - lastStatusCek) >= 10 then refresh_status(); lastStatusCek = os.time() end
        gambar_tabel(isi)   -- v4.10: redraw tabel dari cache (instan)
        local now  = os.time()

        -- v6.60: CEK CAPTCHA BERKALA tiap 45 detik. Deteksi captcha gak boleh
        -- cuma nebeng jalur nyangkut-home/auto-rejoin (banyak & ruwet). Di sini
        -- worker cek client yang RUNNING tapi GAK lapor (kandidat kena captcha):
        -- bawa ke depan, dump uiautomator, cari penanda captcha. Kena -> tandai
        -- (badge panel) + skip; enggak -> clear. Satu client per ronde (gak berat).
        -- v6.84: cek captcha CUMA pas TIDAK standby (mati=false). Pas standby
        -- (FORCE dari panel belum dipencet), worker gak buka client -> gak perlu
        -- cek captcha (biar gak dump [paksa] terus pas standby). Client yang
        -- jalan pas standby (sisa/manual) tetep aman -- cek captcha nyala lagi
        -- pas FORCE.
        -- v6.85: cek captcha CUMA kalau client UDAH PERNAH DIBUKA (lastOpen > 0).
        -- Dulu cek captcha jalan tiap 45 detik dari AWAL loop -- pas worker baru
        -- jalan (client belum kebuka), udah dump [paksa] buat client sisa/latar
        -- yang kebetulan jalan -> dump percuma kepagian. Sekarang nunggu open_all
        -- jalan dulu (client beneran dibuka worker) baru cek captcha.
        -- v7.10: DUMP ALL tiap 90 detik. Ganti dari "1 kandidat per ronde (30s)"
        -- -- yang suka ke-skip timing (iterasi lama -> jarang kejalan) -- jadi
        -- DUMP SEMUA client sekaligus tiap 90s. Tiap client yang idup + gak lapor
        -- fresh + belum ketandai captcha -> cek dump uiautomator (captcha/error).
        -- Konsisten: gak ada yang ke-skip, semua kena giliran tiap 90 detik.
        if false then  -- v7.49: cek captcha DIMATIIN (ganti loop grafis)
            lastCekCaptcha = now
            local statCap = api_get(cfg, "/stat") or ""
            -- CLEAR captcha buat client yang UDAH lapor fresh (masuk game = solved)
            for _, pkgC in ipairs(split(cfg.pkgs or "")) do
                if KICK_DIURUS["captcha:" .. pkgC] then
                    local akC = mapAkun and mapAkun[pkgC]
                    if akC and bridge_fresh(statCap, akC) then
                        tambahLog("CAPTCHA kelar: " .. akC .. " (udah masuk game)")
                        KICK_DIURUS["captcha:" .. pkgC] = nil
                    end
                end
            end
            -- v7.45: TEMBAK-NOLAPOR DIHAPUS (user minta). Client hidup + gak lapor
            -- gak ditembak dari sini lagi -- biarin, ketangkep jalur lain (mati
            -- bareng / diem / nyangkut-home). Blok ini sekarang CUMA clear captcha
            -- (di atas) buat client yang udah masuk game.
        end

        -- v6.48: CEK GANTI AKUN. Buat tiap client yang abis di-LOGIN (target
        -- kesimpen + jadwal cekganti), pas waktunya (60s) lewat: bandingin akun
        -- ASLI di client (dari cookie) vs TARGET. Belum ganti -> lapor alasan
        -- (log + panel) + AUTO re-suntik (kecuali cookie invalid/ban -> stop,
        -- nunggu user ganti cookie). Re-suntik: client dikeluarin dulu, masuk lagi.
        for _, pkgC in ipairs(split(cfg.pkgs or "")) do
            local pkgPend = pkgC:gsub("com%.roblox%.", "")
            local target = KICK_DIURUS["target:" .. pkgPend]
            local jadwal = KICK_DIURUS["cekganti:" .. pkgPend]
            if target and jadwal and now >= jadwal then
                -- baca akun asli di client (dari cookie, timeout biar gak hang)
                local dbC = "/data/data/" .. pkgC .. "/app_webview/Default/Cookies"
                local hK = io.popen(("timeout 8 su -c %s 2>/dev/null"):format(shq(
                    "/data/data/com.termux/files/usr/bin/sqlite3 " .. dbC ..
                    " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
                local ckK = hK and hK:read("*all") or ""
                if hK then hK:close() end
                ckK = cookie_terpanjang(ckK or "")
                local asli = (ckK ~= "" and ckK:find("_|WARNING")) and uname_dari_cookie(ckK) or ""

                -- v7.00: DEBUG -- tampilin cookie/akun apa yang BENERAN kepakai di
                -- client (setelah masuk game), biar ketauan cookie kita menang apa
                -- ke-timpa Roblox. Panjang cookie + akun yang kebaca vs target.
                local pjDbg = ckK ~= "" and #ckK or 0
                info((">>> DEBUG %s: client PAKAI akun '%s' (cookie %d char) | target: '%s' | %s"):format(
                    pkgPend, asli ~= "" and asli or "(kosong)", pjDbg, target,
                    asli == target and "COCOK âœ“" or "BEDA âœ—"))

                if asli == target then
                    -- BERHASIL ganti
                    ok(("GANTI AKUN OK: %s udah jadi %s"):format(pkgPend, target))
                    KICK_DIURUS["target:" .. pkgPend] = nil
                    KICK_DIURUS["cekganti:" .. pkgPend] = nil
                    KICK_DIURUS["retry:" .. pkgPend] = nil
                    KICK_DIURUS["gantigagal:" .. pkgPend] = nil
                else
                    -- BELUM ganti -- cari alasan
                    local sebab
                    local keadaan = cek_cookie_roblox(ckK ~= "" and ckK or nil)
                    if ckK == "" or not ckK:find("_|WARNING") then
                        sebab = "cookie gak kebaca di client"
                    elseif keadaan == "ban" then
                        sebab = "cookie KENA BAN"
                    elseif keadaan == "dead" then
                        sebab = "cookie MATI (invalid)"
                    elseif asli ~= "" and asli ~= target then
                        sebab = "masih akun lama (" .. asli .. ")"
                    else
                        sebab = "belum masuk / nyangkut"
                    end
                    -- cookie invalid/ban -> STOP, nunggu user ganti cookie
                    if keadaan == "ban" or keadaan == "dead" then
                        warn(("GANTI GAGAL: %s -> %s. Sebab: %s"):format(pkgPend, target, sebab))
                        warn("  Stop re-suntik -- ganti cookie dulu (fresh).")
                        KICK_DIURUS["gantigagal:" .. pkgPend] = target .. "|" .. sebab
                        KICK_DIURUS["target:" .. pkgPend] = nil
                        KICK_DIURUS["cekganti:" .. pkgPend] = nil
                    else
                        -- v6.92: BATESI re-suntik MAKS 2x. User minta: yang gagal
                        -- JANGAN dicoba terus -- setelah 2x gagal, STOP + lapor
                        -- panel + log jelas kenapa. Dulu re-suntik selamanya
                        -- (muter nyoba client yang gak mau ganti).
                        local retry = (KICK_DIURUS["retry:" .. pkgPend] or 0) + 1
                        KICK_DIURUS["retry:" .. pkgPend] = retry
                        if retry > 2 then
                            -- STOP -- udah 2x gagal, gak dicoba lagi
                            warn((">>> GANTI AKUN GAGAL: %s -> %s <<<"):format(pkgPend, target))
                            warn(("    Sebab: %s. Udah dicoba %d kali, STOP."):format(sebab, retry - 1))
                            warn("    Client ini GAK diproses lagi. Cek cookie/ganti dari panel.")
                            KICK_DIURUS["gantigagal:" .. pkgPend] = target .. "|" .. sebab .. " (gagal " .. (retry-1) .. "x, stop)"
                            KICK_DIURUS["target:" .. pkgPend] = nil
                            KICK_DIURUS["cekganti:" .. pkgPend] = nil
                        else
                            -- masih boleh coba lagi (< 2x)
                            warn(("GANTI belum kelar: %s -> %s. Sebab: %s (coba lagi #%d)"):format(
                                pkgPend, target, sebab, retry))
                            KICK_DIURUS["gantigagal:" .. pkgPend] = target .. "|" .. sebab .. " (coba #" .. retry .. ")"
                            -- v8.06: force-stop 1 client (pkgC) doang buat re-login
                            -- akun baru. su -c biar konsisten. Cuma pas ganti akun
                            -- (manual dari panel), bukan jalur otomatis.
                            sh_silent("su -c 'am force-stop " .. pkgC .. "'")
                            os.execute("sleep 2")
                            os.execute(("timeout 120 %s login %s %s"):format(
                                (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium",
                                target, pkgPend))
                            KICK_DIURUS["cekganti:" .. pkgPend] = os.time() + 60
                        end
                    end
                end
            end
        end

        -- v6.84: definisi `mati` (STANDBY/STOP) DIPINDAH ke sini (dari bawah) --
        -- biar cek lisensi & cek cookie standby (di bawah) bisa tau lagi standby
        -- apa nggak. Dulu `mati` didefinisi SETELAH cek lisensi -> nil -> cek
        -- standby gak pernah jalan.
        -- v8.61: update MODE_JALAN dari perintah EKSPLISIT (FORCE/STANDBY/STOP).
        -- PLACE:/GRID: gak nyentuh MODE_JALAN -> gak ngubah standby jadi jalan.
        do
            local u = isi:upper()
            if u:find("FORCE") or u:find("REJOIN") or u:find("TEMBAK") then MODE_JALAN = true
            elseif u:find("STANDBY") or u:find("STOP") then MODE_JALAN = false end
        end
        -- mati = kebalikan MODE_JALAN. Dulu dicek dari `isi` sekarang doang -> PLACE/
        -- GRID (yg nimpa STANDBY) bikin mati=false salah. Sekarang dari state.
        local mati = not MODE_JALAN

        -- v8.23: AUTO-DPI 127 pas STANDBY (sekali). User nemu 127 = tampilan pas
        -- (kecil, muat banyak). Set via `wm density 127` + broadcast refresh biar
        -- UI langsung baca ulang (gak aneh/campur). Cek dulu -- kalau udah 127, skip.
        if mati and not _G.VELIUM_DPI_SUDAH then
            (function()
                local d = shell_jalan("wm density", 6) or ""
                local cur = tonumber(d:match("Override density:%s*(%d+)"))
                    or tonumber(d:match("Physical density:%s*(%d+)"))
                if cur == 127 then
                    _G.VELIUM_DPI_SUDAH = true
                else
                    -- set + refresh UI (broadcast config changed biar gak campur)
                    shell_jalan("wm density 127", 8)
                    os.execute("sleep 1")
                    shell_jalan("am broadcast -a android.intent.action.CONFIGURATION_CHANGED", 6)
                    os.execute("sleep 1")
                    if tonumber((shell_jalan("wm density", 6) or ""):match("Override density:%s*(%d+)")) == 127 then
                        ok("DPI diset 127 (standby)")
                        _G.VELIUM_DPI_SUDAH = true
                    else
                        warn("Set DPI 127 gagal (cek root) -- coba lagi ronde depan")
                    end
                end
            end)()
        end

        -- v6.14: CEK LISENSI BERKALA tiap 60 detik. Kalau lisensi Delta HILANG
        -- (file kosong = key habis), langsung bypass -- gak nunggu ronde buka
        -- client (reopen_sec 5 menit). Jadi begitu key habis, key baru diambil
        -- dalam <1 menit, bukan nunggu 5 menit. auto_key harus ON.
        -- v9.26: CEK SETTING PANEL. User: kadang perintah RESTART telat/
        -- ke-nimpa perintah lain. Fix: worker cek /setting-tim sendiri -- kalau ts
        -- BERUBAH (panel ganti place/grid) -> RESTART SENDIRI pakai setting baru.
        -- Gak perlu nunggu perintah RESTART terpisah (yg bisa telat/ke-nimpa).
        -- v9.34: interval 15s -> 5s (tiap poll). User: start dari panel config
        -- kolom baru, worker telat nangkep (nunggu 15s). Sekarang tiap poll cek.
        if (now - lastSettingCek) >= 5 then
            lastSettingCek = now
            local rS = api_get(cfg, "/setting-tim?tim=" .. cfg.tim)
            local tsBaru = ambil_num(rS, "ts") or 0
            if tsBaru > 0 and tsBaru ~= (SETTING_TS_TERAKHIR or 0) then
                local sPlace = ambil_str(rS, "place") or ""
                local sGrid = ambil_num(rS, "grid") or 0
                local sServer = ambil_str(rS, "server") or ""
                -- v9.179: SERVER PREFIX NENTUIN DUNIA. Bug user: ganti server w1-private
                -- tapi place nyangkut W2 (field place di backend ketimpa denyut/lapor
                -- worker -> placeBeda=false -> gak restart -> client tetep W2). Fix:
                -- derive place dari server (w1-* = W1 lama, w2-* = W2 FALL). Server yg
                -- user pilih = dunia yg diinginkan, jadi place WAJIB ikut server.
                if sServer:find("^w1") then sPlace = "97598239454123"   -- v9.191: W1 ASLI (klasik)
                elseif sServer:find("^w2") then sPlace = "126987765280963" end
                -- v9.180: pakai_ps dari server -- "*-private" -> getps ambil PS, "*-public"
                -- -> public. Bug user: w1-private tapi client masuk PUBLIC (getps di-skip
                -- buat W1). Sekarang server nentuin PS: private = getps, public = gak.
                if sServer ~= "" then cfg.pakai_ps = (sServer:find("private") ~= nil) end
                -- v9.31: cek place/grid BENERAN beda dari yg dipakai (bukan cuma
                -- ts naik). Bug user: panel PUT place & grid TERPISAH -> ts naik
                -- 2x -> worker restart 2x (backup nabrak). Sekarang update ts
                -- diam2 kalau nilai sama, restart CUMA kalau place/grid beneran beda.
                local placeBeda = (sPlace ~= "" and sPlace ~= cfg.place_id)
                local gridBeda = (sGrid > 0 and sGrid ~= (tonumber(cfg.grid_kolom) or 0))
                -- v9.62: cek SERVER beda juga (PS/public/world mode). User: ubah
                -- server ke public (place sama) -> setting beda -> harus restart.
                -- Dulu cuma cek place/grid -> server beda gak ke-detect -> gak restart.
                local serverBeda = (sServer ~= "" and sServer ~= (SERVER_TERAKHIR or ""))
                -- v9.71: DEBUG -- log server kebaca dari backend + baseline (biar
                -- keliatan kenapa "server sama"). User: ganti private->public tapi
                -- worker bilang server sama.
                info(("[debug-server] backend='%s' | terakhir='%s' | beda=%s"):format(
                    sServer ~= "" and sServer or "(kosong)",
                    SERVER_TERAKHIR ~= "" and SERVER_TERAKHIR or "(kosong)",
                    tostring(serverBeda)))
                SETTING_TS_TERAKHIR = tsBaru   -- update ts (biar gak cek ulang terus)
                if sServer ~= "" then SERVER_TERAKHIR = sServer end
                if not (placeBeda or gridBeda or serverBeda) then
                    -- ts naik tapi nilai sama (mis. panel set field lain) -> gak restart
                    info("Setting-tim ts naik tapi place/grid/server sama -- gak restart")
                    goto lewatSetting
                end
                if serverBeda then
                    info("Server BEDA (" .. tostring(SERVER_TERAKHIR) .. " -> " .. sServer .. ") -- restart pakai server baru")
                end
                warn("SETTING PANEL BERUBAH (place/grid beda) -> RESTART sendiri pakai setting baru")
                SETTING_TS_TERAKHIR = tsBaru
                if sPlace ~= "" then cfg.place_id = sPlace end
                if sGrid > 0 then cfg.grid_kolom = sGrid end
                pcall(function() save_config(cfg) end)
                info(("  setting baru: place=%s grid=%d kolom"):format(tostring(cfg.place_id), tonumber(cfg.grid_kolom) or 0))
                -- v9.31: kalau place W2 FALL, AMBIL GETPS (PS link) DULU sebelum
                -- restart. Bug user: restart dari setting kejadian SEBELUM denyut
                -- sempet auto-getps -> ps_link kosong -> client masuk PUBLIC (bukan
                -- private). Ambil getps di sini biar accessCode siap pas buka.
                if cfg.place_id == "126987765280963" then
                    -- v9.129: AUTO-getps DIBUANG (user minta manual). Dulu di sini
                    -- jalanin 'velium getps' (block 2 menit) sebelum restart. Sekarang
                    -- cuma BACA /ps-list (PS link dari getps MANUAL yg udah lo ketik).
                    info("  W2 FALL -> baca PS link yg udah ada (getps manual)...")
                    KICK_DIURUS["getps_jalan"] = os.time()   -- tandai: refresh cuma baca
                    do
                        local dapet = false
                        for cobaPs = 1, 3 do
                            pcall(function() refresh_ps_getps() end)
                            local ada = 0
                            for _, pkg in ipairs(split(cfg.pkgs)) do
                                if mapLink[pkg] and mapLink[pkg] ~= "" then ada = ada + 1 end
                            end
                            if ada > 0 then
                                info(("  [ps-getps] %d client dapet PS link (dari getps manual)"):format(ada))
                                dapet = true
                                break
                            end
                            os.execute("sleep 1")
                        end
                        if not dapet then
                            warn("  [ps-getps] 0 PS link -> jalanin 'velium getps' MANUAL dulu, atau client PUBLIC")
                        end
                    end
                end
                -- RESTART sendiri: tutup semua + grid 2x + buka fresh pakai setting baru
                MODE_JALAN = true
                SUDAH_GRID = false; GRID_CACHE = nil
                -- v9.32: baca /start-pilih (client yg DICENTANG di panel) -> restart
                -- CUMA client itu. Bug user: setting 6 client tapi worker buka 10.
                -- Kalau pilih ada -> RESTART:akun1,akun2,... Kalau kosong -> semua.
                local isiRestart = "RESTART"
                do
                    -- v9.37: /start-pilih return ARRAY ("pilih":["a","b"]) BUKAN
                    -- string. ambil_str (cari "pilih":"...") GAGAL -> pilihStr kosong
                    -- -> fallback ADA AKUN -> buka SEMUA (10 akun = 10 client). Bug
                    -- user: "selalu gitu kalau 10 akun". Fix: ambil isi dalam [...]
                    -- langsung dari JSON array, parse nama akun di dalamnya.
                    local rP = api_get(cfg, "/start-pilih?tim=" .. cfg.tim)
                    local arrIsi = tostring(rP or ""):match('"pilih"%s*:%s*%[(.-)%]')
                    if arrIsi and arrIsi ~= "" then
                        -- parse nama akun dari isi array ("a","b","c")
                        local daftar = {}
                        for nm in arrIsi:gmatch('"([^"]+)"') do daftar[#daftar+1] = nm end
                        if #daftar > 0 then
                            isiRestart = "RESTART:" .. table.concat(daftar, ",")
                            info(("  client dipilih di panel: %d client -> %s"):format(#daftar, table.concat(daftar, ",")))
                        end
                    end
                    -- v9.34: kalau /start-pilih KOSONG -> jangan pakai SEMUA cfg.pkgs
                    -- (bisa 10 client hasil scan, padahal cuma 6 punya akun). Fallback
                    -- ke client yg ADA AKUNnya (mapAkun). Bug user: 6 akun ke-assign
                    -- tapi cfg.pkgs=10 -> restart buka 10 (4 client kosong tanpa akun).
                    if isiRestart == "RESTART" and mapAkun then
                        local akunClient = {}
                        for _, pkg in ipairs(split(cfg.pkgs)) do
                            local u = mapAkun[pkg]
                            if u and tostring(u) ~= "" then
                                local nm = pkg:gsub("com%.roblox%.", "")
                                akunClient[#akunClient+1] = nm
                            end
                        end
                        if #akunClient > 0 and #akunClient < #split(cfg.pkgs) then
                            isiRestart = "RESTART:" .. table.concat(akunClient, ",")
                            info(("  /start-pilih kosong -> pakai %d client yg ADA AKUN (dari %d total scan)"):format(
                                #akunClient, #split(cfg.pkgs)))
                        end
                    end
                end
                PKGS_AKTIF = restart_kerjakan(cfg, isiRestart, mapAkun, mapLink, ada_stop)
                if PKGS_AKTIF and #PKGS_AKTIF > 0 then simpan_aktif(cfg) end   -- v9.89: simpen state
                refresh_status(); lastStatusCek = os.time()
                lapor(cfg, isiRestart, cacheRun); lastStatus = os.time()
                ::lewatSetting::
            end
        end

        -- v7.70: cek lisensi berkala TIAP 10 MENIT (user minta, dulu 60 detik).
        -- Kalau KEY API HILANG -> mulai dari awal LAGI (kayak Start): bypass key
        -- dulu, terus buka semua client (open_all fast=false = jalur bypass +
        -- buka ulang, persis start).
        if cfg.auto_key == true and cfg.executor ~= "arceus" and (now - lastLisensiCek) >= 600 then
            lastLisensiCek = now
            local kd = lisensi_keadaan(cfg)   -- v7.69: udah retry 3x di dalam
            -- v8.25: LOG status lisensi tiap 10 menit (user minta). Kalau key masih
            -- ada -> tampilin "lisensi aktif" biar keliatan worker + key hidup.
            if kd == "ada" then
                ok("Lisensi Delta AKTIF (cek berkala 10 menit)")
                KICK_DIURUS["lisensi_standby_warned"] = nil   -- v9.50: reset biar info standby muncul lagi kalau hilang lagi
            end
            if kd == "hilang" and (now - (BYPASS_TERAKHIR or 0)) > 300 then
                -- v9.55: lisensi hilang -> bypass CUMA kalau UDAH pernah Start
                -- (MODE_JALAN=true). User: STANDBY SEBELUM Start belum tau config
                -- (grid/jumlah client) -- bypass butuh grid (ukuran window buat titik
                -- tap key). Jadi belum Start -> jgn bypass (nunggu Start biar tau grid
                -- dulu). UDAH Start (config keset) -> lisensi hilang -> LANGSUNG bypass
                -- (pulihin, gak nunggu pencet Start lagi).
                if not MODE_JALAN then
                    -- belum pernah Start -> config belum tau -> tunda bypass. Info sekali.
                    if not KICK_DIURUS["lisensi_standby_warned"] then
                        KICK_DIURUS["lisensi_standby_warned"] = true
                        info("Lisensi Delta hilang -- bypass nunggu Start (config grid belum keset)")
                    end
                    BYPASS_TERAKHIR = now   -- tandai biar gak spam
                elseif lisensi_false_alarm(cfg) then
                    warn("Lisensi kebaca 'hilang' TAPI terverifikasi masih ADA -> FALSE ALARM, SKIP")
                else
                    warn("Lisensi HILANG -- FOKUS PULIHIN (bypass key + buka client)")
                    SUDAH_GRID = false; GRID_CACHE = nil
                    -- udah Start -> PKGS_AKTIF keset (grid tau). pertahankan (jalan 6 -> 6).
                    -- v9.57: kalau PKGS_AKTIF nil (worker re-exec, belum ke-set dari
                    -- RESTART), INFER client aktif dari perintah DB (FORCE/RESTART:daftar).
                    -- Bug user: bypass grid 10 (4x3) pas PKGS_AKTIF nil -> grid salah.
                    local onlyLis = (PKGS_AKTIF and #PKGS_AKTIF > 0) and PKGS_AKTIF or nil
                    if not onlyLis then
                        local rP = api_get(cfg, "/perintah?tim=" .. cfg.tim) or ""
                        local isiP = ambil_str(rP, "isi") or ""
                        local daftarP = isiP:match("FORCE:([%w%.%_,]+)") or isiP:match("RESTART:([%w%.%_,]+)")
                        if daftarP then
                            local setP = {}
                            for a in daftarP:gmatch("[^,]+") do setP[a] = true end
                            local pkgsP = {}
                            for _, pkg in ipairs(split(cfg.pkgs)) do
                                local u = mapAkun and mapAkun[pkg]
                                local nm = pkg:gsub("com%.roblox%.", "")
                                -- v9.122: rotasi_on -> cuma tim 1 (tim 2 standby)
                                if (setP[u] or setP[pkg] or setP[nm]) and not rotasi_lewat(cfg, pkg) then pkgsP[#pkgsP+1] = pkg end
                            end
                            if #pkgsP > 0 then
                                onlyLis = pkgsP
                                PKGS_AKTIF = pkgsP   -- set sekalian biar grid konsisten
                                info(("  (bypass: %d client aktif dari perintah DB)"):format(#pkgsP))
                            end
                        end
                    end
                    open_all(cfg, onlyLis, function() return ada_perintah_baru(cfg, isi) end, nil, mapLink, mapAkun, false, true)
                    refresh_status(); lastStatusCek = os.time()
                    BYPASS_TERAKHIR = now
                end
            end
        end

        -- v6.84: CEK COOKIE AKUN LAMA pas STANDBY (tiap 5 menit). Cek cookie yang
        -- lagi kepasang di tiap client masih hidup apa nggak -> setor status ke
        -- panel. Jadi SEBELUM start, udah ketauan cookie mana yang mati (badge
        -- panel) -> bisa langsung ganti. Cuma pas standby (pas jalan, cek cookie
        -- udah ada di jalur lain). velium cekcookie = cek semua akun tim, setor CF.
        -- v9.131: CEK COOKIE STANDBY DIBUANG (user minta). Dulu tiap 5 menit pas
        -- standby jalanin 'velium cekcookie' (timeout 180 = block 3 menit) -> bikin
        -- START lama (nunggu cek cookie dulu sebelum buka client). Sekarang skip.
        -- Cookie tetep kecek di jalur lain pas client jalan.
        if false and mati and (now - lastCookieStandby) >= 300 then
            lastCookieStandby = now
            info("Cek cookie akun lama (standby) -- mastiin masih hidup...")
            os.execute(("timeout 180 %s cekcookie"):format(
                (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium"))
            refresh_status(); lastStatusCek = os.time()
        end

        -- v4.3: narik link private server dari panel. kalau panel udah pernah set
        -- (ts>0), pakai link panel (walau kosong = public). kalau panel belum
        -- pernah set, biarin cfg._ps_override nil -> build_url pakai link lokal.
        do
            local rps = api_get(cfg, "/ps?tim=" .. cfg.tim)
            local psTs = ambil_num(rps, "ts") or 0   -- v4.53: angka, bukan teks
            if psTs > 0 then
                local link = ambil_str(rps, "link") or ""
                -- _ps_last nyimpen link terakhir dari panel biar gak spam log.
                -- pakai flag terpisah, bukan _ps_override, biar "" (public) kebedain
                -- dari nil (panel belum set).
                if link ~= cfg._ps_last then
                    cfg._ps_last = link
                    cfg._ps_override = link
                    info("PS dari panel: " .. (link ~= "" and link or "(public)"))
                end
            end
        end

        -- v4.4: CLOSE = tutup paksa semua client (Roblox ketutup, akun keluar).
        -- REJOIN = tutup paksa DULU, terus buka lagi (fresh). beda dari FORCE yg
        -- cuma mastiin kebuka (client yg udah jalan dibiarin).
        -- pakai penanda biar gak loop terus (perintah nyangkut di DB).
        -- v4.4: CLOSE / REJOIN ditangani dulu. skip_sisa=true -> lewati blok
        -- FORCE/STANDBY di bawah biar gak dobel-buka. (pakai flag, bukan goto,
        -- karena goto gak boleh lompatin deklarasi lokal di Luau.)
        local skip_sisa = false
        local U = isi:upper()

        -- v6.27: LOGIN PALING PRIORITAS. Pas panel suntik cookie (LOGIN:akun:client),
        -- worker langsung jalanin ITU DULU, skip semua perintah lain ronde ini.
        -- Biar akun langsung keganti gak nunggu antrian (buka client dll).
        local loginPrioritas = false
        do
            local akunL, clientL = isi:match("^LOGIN:([^:]+):([^:]+)")
            -- v6.34: cuma proses kalau BELUM diproses (isi beda dari lastIsi).
            -- Karena gak balikin FORCE lagi, backend tetep LOGIN -> tanpa cek ini
            -- LOGIN sama diulang tiap iterasi. isi beda (client/akun lain) = baru.
            if akunL and clientL and isi ~= lastIsi then
                print("")
                print(C.BOLD .. C.C .. ">>> JALANIN PERINTAH LOGIN <<<" .. C.N)
                info(("Suntik cookie: %s -> client %s"):format(akunL, clientL))
                info("(login diprioritasin -- perintah lain di-skip ronde ini)")
                -- v6.28: HAPUS tanda mati akun ini. Lo lagi GANTI ke akun ini,
                -- jadi override skip-mati (v6.24). Kalau akun sebelumnya kena
                -- verif/mati & ditandai skip, tanda itu dibuang biar login jalan
                -- & akun baru gak keskip.
                KICK_DIURUS["mati:" .. akunL] = nil
                local pkgL = clientL:find("%.") and clientL or ("com.roblox." .. clientL)
                -- v6.28: cek client valid (ada di config). Kalau yang dikirim
                -- ternyata NAMA AKUN (bug lama panel), pkgL gak ada di pkgs ->
                -- kasih tau, jangan diam.
                local adaClient = false
                for _, pk in ipairs(split(cfg.pkgs or "")) do
                    if pk == pkgL then adaClient = true break end
                end
                if not adaClient then
                    warn(("Client '%s' gak ada di config -- mungkin salah kirim (nama akun?)."):format(
                        pkgL:gsub("com%.roblox%.", "")))
                    warn("  Client valid: " .. (cfg.pkgs or "?"):gsub("com%.roblox%.", ""))
                end
                -- v6.41: timeout 120s biar kalau `velium login` HANG (client beku /
                -- force-stop macet / SQL lock), worker GAK ikut macet -- paksa
                -- berhenti, lanjut. Dulu os.execute nunggu selamanya -> worker
                -- diem total pas login gagal.
                os.execute(("timeout 120 %s login %s %s"):format(
                    (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium",
                    akunL, pkgL:gsub("com%.roblox%.", "")))
                ok(("LOGIN selesai: %s -> %s"):format(akunL, clientL))
                -- v6.33: JANGAN balikin FORCE ke backend. Dulu worker nulis FORCE
                -- abis LOGIN -> pas lo suntik LOGIN client BERIKUTNYA, FORCE ini
                -- keburu nimpa -> LOGIN kedua ilang (cuma perintah pertama jalan).
                -- Cukup tandai lokal aja; worker lanjut normal, backend dibiarin
                -- (LOGIN kehapus sendiri pas kebaca, atau ketimpa perintah lo
                -- berikutnya -- yang justru kita mau).
                lastIsi = isi   -- tandai LOGIN ini udah diproses (jgn ulang)
                refresh_status(); lastStatusCek = os.time()
                gambar_tabel(isi)
                loginPrioritas = true   -- skip semua perintah lain ronde ini
                skip_sisa = true
            end
        end

        if loginPrioritas then
            -- LOGIN udah dijalanin, lewati semua handler perintah lain ronde ini
        elseif U:find("REJOIN") then
            if isi ~= lastIsi then
                lastIsi = isi
                -- v4.15: REJOIN:namaakun = rejoin CLIENT tertentu (bukan semua).
                -- v4.20: bisa BANYAK akun, pisah koma: REJOIN:akun1,akun2 -> rejoin
                -- per-client masing-masing (tutup 1, buka 1). JANGAN kill all.
                -- REJOIN doang (tanpa :akun) = rejoin SEMUA (kill all) -- buat ganti
                -- server SEMUA client sekaligus.
                local akunTarget = isi:match("REJOIN:(.+)")
                if akunTarget then
                    -- parse daftar akun (pisah koma)
                    local daftarAkun = {}
                    for nm in akunTarget:gmatch("[^,]+") do
                        nm = nm:gsub("%s+", "")
                        if nm ~= "" then daftarAkun[#daftarAkun+1] = nm end
                    end
                    refresh_ps(); pcall(refresh_ps_getps)   -- v8.53: getps juga (accessCode per akun ke-refresh)
                    -- v4.61: kumpulin dulu, TUTUP BARENGAN, baru buka bertahap.
                    -- Perintah dari panel jadi kerasa langsung -- bukan nunggu
                    -- client 1 kelar dulu baru nyentuh client 2.
                    local pkgRejoin, namaRejoin = {}, {}
                    for _, namaAkun in ipairs(daftarAkun) do
                        local pkgTarget = nil
                        for pkg, ak in pairs(mapAkun) do
                            if ak == namaAkun then pkgTarget = pkg break end
                        end
                        if pkgTarget then
                            pkgRejoin[#pkgRejoin+1]   = pkgTarget
                            namaRejoin[#namaRejoin+1] = namaAkun
                        else
                            RIW.catat("REJOIN", "-", "karena=perintah-panel")
            tambahLog("REJOIN: akun " .. namaAkun .. " gak ketemu di RF ini")
                        end
                    end
                    if #pkgRejoin > 0 then
                        -- semua client tim ikut? tutup sekalian (lebih bersih)
                        local semua = (#pkgRejoin == #split(cfg.pkgs))
                        tambahLog(("REJOIN %d akun: %s"):format(#pkgRejoin, table.concat(namaRejoin, ", ")))
                        close_all(cfg, semua and nil or pkgRejoin, mapLink)
                        os.execute("sleep 2")
                        for i, pkg in ipairs(pkgRejoin) do
                            open_one(cfg, pkg, mapLink[pkg], "rejoin-manual-panel")
                            if i < #pkgRejoin then os.execute("sleep " .. (cfg.stagger_sec or 10)) end
                        end
                        notify("Velium "..cfg.tim, "rejoin " .. #pkgRejoin .. " akun")
                    end
                else
                    -- v9.46: REJOIN polos -- kalau lagi jalan N client (PKGS_AKTIF),
                    -- cuma rejoin ITU (bukan semua 10). Bug user: jalan 6 client,
                    -- REJOIN polos -> buka semua 10. only = PKGS_AKTIF kalau ada.
                    local onlyRejoin = (PKGS_AKTIF and #PKGS_AKTIF > 0) and PKGS_AKTIF or nil
                    warn(onlyRejoin
                        and ("REJOIN dari panel -> tutup+buka " .. #onlyRejoin .. " client aktif")
                        or "REJOIN dari panel -> tutup semua, buka lagi")
                    close_all(cfg, onlyRejoin, mapLink)
                    os.execute("sleep 3")
                    local function batal_r()
                        -- v9.63: PAKSA/RESTART/STANDBY baru -> nyela loop rejoin
                        return ada_perintah_baru(cfg, isi)
                    end
                    refresh_ps(); pcall(refresh_ps_getps)
                    local function lapor_rejoin()
                        refresh_status(); lastStatusCek = os.time()
                        gambar_tabel(isi)
                        lapor(cfg, isi, cacheRun)
                    end
                    local h = open_all(cfg, onlyRejoin, batal_r, lapor_rejoin, mapLink, mapAkun, true)
                    ok(string.format("REJOIN kelar: %d jalan, %d gagal", h.ok, h.gagal))
                    notify("Velium "..cfg.tim, "REJOIN -> "..h.ok.." client")
                    lastOpen = os.time()
                    lastStatus = 0
                end
            end
            skip_sisa = true
        elseif U:find("REBOOT") then
            -- v9.80: REBOOT RF dari panel. Lapor dulu ke panel (biar keliatan lagi
            -- reboot), reset perintah ke FORCE (biar pas nyala lagi worker langsung
            -- buka client, gak nyangkut REBOOT), baru reboot. Worker auto-jalan lagi
            -- abis nyala via Termux:Boot (~/.termux/boot/velium).
            if isi ~= lastIsi then
                lastIsi = isi
                -- v9.83: CEK boot siap dulu. Kalau Termux:Boot belum kepasang,
                -- reboot = worker gak nyala lagi = RF MATI. Batal + lapor ke panel.
                local siap, alasan = boot_siap()
                if not siap then
                    warn("REBOOT DIBATALIN -- " .. alasan)
                    tambahLog("REBOOT batal: " .. alasan .. " (RF bakal mati kalau tetep reboot)")
                    notify("Velium "..cfg.tim, "REBOOT batal: " .. alasan)
                    -- balik FORCE biar lanjut normal (gak nyangkut REBOOT)
                    pcall(function()
                        tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":%s}', jstr(cfg.tim), jstr(force_str(cfg, mapAkun))))
                    end)
                    lapor(cfg, "REBOOT-BATAL", cacheRun)
                    skip_sisa = true
                    goto lewatReboot
                end
                warn("REBOOT dari panel -> RF di-restart, worker STANDBY abis nyala (nunggu Start)")
                tambahLog("REBOOT: RF di-restart dari panel -> standby (pencet Start buat buka client)")
                notify("Velium "..cfg.tim, "RF reboot -- STANDBY, pencet Start buat mulai")
                -- v9.108: abis REBOOT dari panel -> STANDBY (JANGAN auto-buka client).
                -- User: pas reboot jangan langsung nyala, nunggu Start dari panel.
                -- Dulu di-set FORCE (langsung buka). Sekarang STANDBY -> nunggu.
                pcall(function()
                    api_post(cfg, "/perintah", string.format('{"tim":%s,"isi":"STANDBY"}', jstr(cfg.tim)), "PUT")
                end)
                lapor(cfg, "REBOOT", cacheRun)
                os.execute("sleep 2")   -- kasih waktu lapor + reset perintah kekirim
                -- reboot: svc power reboot (halus) dulu, 8s, fallback reboot biasa
                os.execute("su -c 'svc power reboot' >/dev/null 2>&1 &")
                os.execute("sleep 8")
                os.execute("su -c 'reboot' >/dev/null 2>&1 &")
                os.execute("sleep 30")   -- nunggu HP mati
            end
            ::lewatReboot::
            skip_sisa = true
        elseif U:find("FRONT") then
            if isi ~= lastIsi then
                lastIsi = isi
                local n = front_all(cfg, mapLink)
                tambahLog("FRONT: " .. n .. " client dibawa ke depan")
                notify("Velium "..cfg.tim, "semua client ke depan")
            end
            skip_sisa = true
        elseif U:find("TUGAS") then
            -- v4.55: panel minta rincian "tim ini lagi ngapain & mau ngapain".
            -- Semua ditulis lewat tambahLog biar ikut kekirim ke panel juga.
            if isi ~= lastIsi then
                lastIsi = isi
                setAksi("nyusun laporan tugas")
                local st  = api_get(cfg, "/stat")
                local sup = api_get(cfg, "/suplai")
                local skrgSrv = ambil_num(st, "skrg") or os.time()

                tambahLog("=== TUGAS " .. cfg.tim .. " ===")
                local nJalan, nBeku, nOff = 0, 0, 0
                for _, pkg in ipairs(split(cfg.pkgs)) do
                    local short = pkg:gsub("com%.roblox%.", "")
                    local akun  = mapAkun[pkg] or "?"
                    local ps    = mapPsNama[pkg] or "public"
                    local ada   = pkg_running(pkg)
                    local lapor = akun ~= "?" and bridge_ts(st, akun) or nil
                    local umur  = lapor and (skrgSrv - lapor) or nil
                    local kead
                    if not ada then kead = "OFF (window gak ada)"; nOff = nOff + 1
                    elseif umur and umur <= FRESH_WINDOW then
                        kead = "jalan (lapor " .. umur .. "s lalu)"; nJalan = nJalan + 1
                    else
                        kead = "BEKU (" .. (umur and (umur .. "s gak lapor") or "belum pernah lapor") .. ")"
                        nBeku = nBeku + 1
                    end
                    tambahLog(short .. " | " .. akun .. " | " .. ps .. " | " .. kead)
                end
                tambahLog(("ringkas: %d jalan, %d beku, %d off"):format(nJalan, nBeku, nOff))

                -- tugas suplai yang lagi nyangkut di tim ini
                local nAktif = ambil_num(sup, "jumlahAktif") or 0
                local alasan = ambil_str(sup, "alasan") or ""
                local psTuju = ambil_str(sup, "psTujuan") or ""
                if nAktif > 0 then
                    tambahLog("suplai: " .. nAktif .. " akun lagi dirutein"
                              .. (psTuju ~= "" and (" (tujuan " .. psTuju .. ")") or ""))
                else
                    tambahLog("suplai: gak ada yang lagi dirutein"
                              .. (alasan ~= "" and (" -- " .. alasan) or ""))
                end
                tambahLog("perintah aktif: " .. (isi ~= "" and isi or "-"))
                notify("Velium "..cfg.tim, "laporan tugas siap")
            end
            skip_sisa = true
        elseif U:find("ROTASI%-TEST") or U:find("ROTASI%-GO") then
            -- v9.137/139: udah diproses di TOP-LOOP (langsung). Di sini cuma skip biar
            -- gak jatuh ke handler ROTASI (yg bakal matiin rotasi). Gak dobel.
            skip_sisa = true
        elseif U:find("ROTASI") then
            -- v9.115: ROTASI:<seed1,seed2> dari panel -> nyalain rotasi + set seed
            -- incaran. "ROTASI:off" -> matiin. Set cfg + save (persist antar restart).
            if isi ~= lastIsi then
                lastIsi = isi
                local isiRot = isi:match("ROTASI:(.*)$") or ""
                isiRot = isiRot:gsub("^%s+", ""):gsub("%s+$", "")
                if isiRot == "" or isiRot:lower() == "off" then
                    cfg.rotasi_on = false
                    warn("ROTASI dimatiin dari panel")
                    tambahLog("Rotasi tim: MATI")
                else
                    -- v9.136: format "seeds|batch|opensec". batch+opensec opsional.
                    -- v9.144: +|dunia opsional (sama/w1/w2/gantian).
                    -- v9.197: extract |PETA=seed:place,... (peta seed->dunia) buat
                    -- worker self-detect tau dunia tiap seed. Buang dulu sebelum parse.
                    local petaGO = isiRot:match("|PETA=(.+)$")
                    if petaGO then
                        cfg.rotasi_peta = petaGO
                        isiRot = isiRot:gsub("|PETA=.+$", "")
                    end
                    local seeds, bt, os2, dn = isiRot:match("^(.-)|(%d+)|(%d+)|(%w+)$")
                    if not seeds then
                        seeds, bt, os2 = isiRot:match("^(.-)|(%d+)|(%d+)$")
                    end
                    if seeds then
                        cfg.rotasi_barang = seeds
                        cfg.rotasi_batch = tonumber(bt)
                        cfg.rotasi_open_sec = tonumber(os2)
                        if dn then cfg.rotasi_dunia = dn:lower() end
                    else
                        cfg.rotasi_barang = isiRot
                    end
                    cfg.rotasi_on = true
                    warn(("ROTASI nyala -> seed: %s | batch=%s open=%ss dunia=%s"):format(
                        cfg.rotasi_barang, tostring(cfg.rotasi_batch or 5), tostring(cfg.rotasi_open_sec or 80), cfg.rotasi_dunia or "sama"))
                    tambahLog("Rotasi tim: NYALA (" .. cfg.rotasi_barang .. ")")
                end
                pcall(function() save_config(cfg) end)
                -- v9.167: ROTASI cuma toggle rotasi, BUKAN stop. Kalau lagi FORCE
                -- (MODE_JALAN), RESTORE command FORCE ke /perintah biar client TETEP
                -- kebuka. ROOT CAUSE bug user: START PAKSA set /perintah=FORCE, tapi
                -- panel NIMPA dgn ROTASI:off -> command FORCE ilang -> client gak
                -- kebuka. Sama kayak CEKCOOKIE yg re-send FORCE abis diproses.
                if MODE_JALAN then
                    pcall(function()
                        local isiForce = force_str(cfg, mapAkun)
                        tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":"%s"}', jstr(cfg.tim), isiForce))
                        lastIsi = isiForce
                    end)
                    info("ROTASI diproses pas FORCE -> restore FORCE (client tetep kebuka)")
                end
                lapor(cfg, isi, cacheRun); lastStatus = os.time()
                skip_sisa = true   -- v9.166: cuma ronde PERTAMA (baru toggle rotasi).
            end
            -- v9.166 FIX: skip_sisa DIPINDAH ke DALAM if (dulu di luar -> tiap ronde
            -- skip). Bug: pas sticky command = "ROTASI:off", tiap ronde skip_sisa=true
            -- -> blok buka+rejoin client (line ~8806) KE-SKIP -> client GAK PERNAH
            -- kebuka. Sama persis bug RESTART yg difix v9.79. Sekarang ROTASI bekas
            -- (sticky, udah diproses) -> skip_sisa=false -> loop antrian buka+rejoin.
        elseif U:find("GRID") then
            -- v8.61: blok GRID LAMA (nata jendela + buka client). SKIP kalau:
            -- (1) "GRID:<kolom>" -- itu diproses blok baru (set grid_kolom, hormatin
            --     STANDBY). Blok lama cuma buat "GRID" polos (nata ulang manual).
            -- (2) lagi STANDBY -- jangan buka client pas standby.
            if isi:find(":") or not MODE_JALAN then
                -- GRID:kolom / standby -> jangan jalanin nata-buka lama.
                -- (blok baru di bawah yg handle GRID:kolom; standby = diem)
                -- v8.63 FIX: JANGAN set lastIsi di sini! Dulu set lastIsi=isi ->
                -- blok baru (gridDari) cek "isi ~= lastIsi" jadi FALSE -> grid_kolom
                -- GAK ke-set -> worker lapor grid 0. Biarin blok baru yg set lastIsi.
                skip_sisa = false   -- biarin lanjut ke blok gridDari
            elseif isi ~= lastIsi then
                lastIsi = isi
                -- v4.82: nata ulang HARUS lewat restart client. App Cloner cuma
                -- baca posisi pas app MULAI, dan nimpa balik pas app DITUTUP --
                -- jadi nulis ke client yang lagi jalan itu percuma dua kali.
                -- Alurnya: tutup semua -> tulis semua -> buka satu-satu.
                setAksi("nata jendela (tutup -> tulis posisi -> buka)")
                -- v9.47: grid buat PKGS_AKTIF (jalan 6 -> grid 6 petak, bukan 10)
                local pkgsGridManual = (PKGS_AKTIF and #PKGS_AKTIF > 0) and PKGS_AKTIF or nil
                local peta, sebabGrid, kol, bar, W, H, lebarC, tinggiC = grid_hitung(cfg, pkgsGridManual)
                if not peta then
                    tambahLog("GRID gagal: " .. tostring(sebabGrid))
                    warn("GRID gagal: " .. tostring(sebabGrid))
                else
                    -- v8.68: log detail -- grid berapa kolom x baris + ukuran layar
                    -- PER CLIENT (biar user bisa cek bener apa nggak).
                    local nC = #split(cfg.pkgs)
                    tambahLog(string.format("GRID: %d kolom x %d baris (%d client) -- layar per client %dx%d px [layar total %dx%d]",
                        kol or 0, bar or 0, nC, lebarC or 0, tinggiC or 0, W or 0, H or 0))
                    info(string.format("GRID diset: %dx%d, per client %dx%d px",
                        kol or 0, bar or 0, lebarC or 0, tinggiC or 0))
                    -- v8.61: pakai close_all_cepat (tutup barengan) bukan close_all
                    -- lama (5s/client). GRID gak perlu jeda App Cloner per-client --
                    -- toh langsung tulis prefs + buka ulang.
                    close_all_cepat(cfg, true)
                    os.execute("sleep 2")

                    local nTulis, nGagal = 0, 0
                    for _, pkg in ipairs(split(cfg.pkgs)) do
                        -- v9.122: rotasi_on -> jangan tata grid tim 2 (standby)
                        if rotasi_lewat(cfg, pkg) then goto lanjutTata end
                        -- v8.67: hapusDulu=true -> buang posisi window LAMA dulu,
                        -- baru tulis grid baru (user minta bener2 bersih, gak nyangkut)
                        local tok, tket = tata_satu(pkg, peta[pkg], true)
                        if tok then nTulis = nTulis + 1
                        else
                            nGagal = nGagal + 1
                            tambahLog("   " .. pkg:gsub("com%.roblox%.","") .. ": " .. tostring(tket))
                        end
                        ::lanjutTata::
                    end
                    tambahLog(("GRID: posisi ketulis %d client%s"):format(
                        nTulis, nGagal > 0 and (", " .. nGagal .. " gagal") or ""))

                    refresh_ps(); pcall(refresh_ps_getps)
                    local function batal_g()
                        -- v9.63: PAKSA/RESTART/STANDBY baru -> nyela loop grid
                        return ada_perintah_baru(cfg, isi)
                    end
                    local function lapor_g()
                        refresh_status(); lastStatusCek = os.time()
                        gambar_tabel(isi)
                        lapor(cfg, isi, cacheRun)
                    end
                    -- v9.47: pertahankan PKGS_AKTIF (jalan 6 -> buka 6, bukan 10)
                    local onlyGrid = (PKGS_AKTIF and #PKGS_AKTIF > 0) and PKGS_AKTIF or nil
                    local h = open_all(cfg, onlyGrid, batal_g, lapor_g, mapLink, mapAkun, true)
                    tambahLog(("GRID: kelar -- %d client kebuka lagi"):format(h.ok))
                    notify("Velium "..cfg.tim, "grid: " .. nTulis .. " jendela ditata")
                    lastOpen = os.time()
                    lastStatus = 0
                end
            end
            if not isi:find(":") and MODE_JALAN then skip_sisa = true end
        elseif U:find("PAKSA") then
            -- v9.62: START PAKSA -- SELALU restart, GAK cek ts/apapun (pasti jalan).
            -- Perintah BARU yg panel lama gak kenal -> guard natural.
            if isi ~= lastIsi then
                lastIsi = isi
                MODE_JALAN = true
                -- v9.66: RESET STATE PENUH -- kayak worker BARU jalan. User: tiap
                -- Start Paksa harus proses BENER2 BARU, buang proses lama total.
                -- Reset: client aktif, cache grid, penanda proses. JANGAN reset
                -- status akun (mati/captcha/ban) + device info (biar gak ilang).
                SUDAH_GRID = false; GRID_CACHE = nil; PKGS_AKTIF = nil
                BYPASS_TERAKHIR = 0
                for k in pairs(KICK_DIURUS) do
                    -- buang penanda PROSES, simpen status akun + device
                    if k == "getps_jalan" or k == "login_tertunda"
                       or k == "lisensi_standby_warned"
                       or k:find("^captcha:") or k:find("^offlama:") or k:find("^diag:") then
                        KICK_DIURUS[k] = nil
                    end
                end
                info("START PAKSA dari panel -- RESET FRESH (kayak worker baru) + restart")
                -- restart_kerjakan baca daftar dari "PAKSA:akun,akun" (sama kayak RESTART:)
                local isiRestart = isi:gsub("^PAKSA", "RESTART")
                PKGS_AKTIF = restart_kerjakan(cfg, isiRestart, mapAkun, mapLink, ada_stop)
                if PKGS_AKTIF and #PKGS_AKTIF > 0 then simpan_aktif(cfg) end   -- v9.89: simpen state
                refresh_status(); lastStatusCek = os.time()
                lapor(cfg, isi, cacheRun); lastStatus = os.time()
                info("START PAKSA selesai -- lanjut buka client")
                -- v9.65: kirim FORCE:daftar ke DB sendiri biar ronde depan buka client.
                -- User: setelah start paksa dia GAK FORCE -> client gak kebuka. Dulu
                -- andelin backend expire RESTART->FORCE, tapi PAKSA gak ke-expire.
                do
                    -- v9.178: SEBELUM nimpa /perintah dgn FORCE:daftar, TANGKEP ROTASI
                    -- yg mungkin udah masuk dari panel (urutan START PAKSA -> ROTASI).
                    -- Kalau gak, FORCE:daftar nimpa ROTASI -> ilang -> antrian ronde
                    -- depan gak tau rotasi -> semua 20 kebuka. Set rotasi_on DI SINI.
                    do
                        local pR = ambil_str(api_get(cfg, "/perintah?tim=" .. cfg.tim), "isi") or ""
                        local uR = pR:upper()
                        if uR:find("ROTASI") and not uR:find("ROTASI%-") then
                            local isiRot = (pR:match("ROTASI:(.*)$") or ""):gsub("^%s+", ""):gsub("%s+$", "")
                            if isiRot ~= "" and isiRot:lower() ~= "off" and not cfg.rotasi_on then
                                cfg.rotasi_on = true
                                cfg.rotasi_barang = isiRot:match("^(.-)|") or isiRot
                                ROT_TIM1 = nil
                                info("[start-paksa] ROTASI ketangkep sebelum FORCE -> rotasi_on=true (Tim 2 STANDBY)")
                            end
                        end
                    end
                    local daftarForce = isi:match("PAKSA:(.+)")
                    local isiForce = daftarForce and ("FORCE:" .. daftarForce) or force_str(cfg, mapAkun)
                    lastIsi = isiForce   -- update biar gak ke-PAKSA-handler lagi
                    pcall(function()
                        tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":"%s"}', jstr(cfg.tim), isiForce))
                    end)
                    info("PAKSA -> FORCE dikirim (client bakal kebuka ronde ini)")
                    _apb_waktu = 0   -- reset cek perintah (fresh ronde depan)
                end
                skip_sisa = true   -- ronde ini skip (baru tutup+grid), ronde depan FORCE buka
            end
            -- v9.64: kalau PAKSA udah diproses (isi==lastIsi, nyangkut di DB), JANGAN
            -- skip_sisa -> biarin loop antrian jalan (buka client + rejoin). Bug user:
            -- PAKSA "selesai" tapi client gak kebuka -- restart_kerjakan cuma tutup+
            -- grid, client kebuka di LOOP ANTRIAN. Dulu skip_sisa=true tiap ronde ->
            -- loop antrian gak pernah jalan -> client nyangkut ketutup.
        elseif U:find("UPDATE%-WORKER") then
            -- v9.111: UPDATE-WORKER dari panel (manual, aman). Download worker versi
            -- baru dari GitHub, validasi, ganti file, restart SESI (launcher loop).
            -- Termux tetep idup, client tetep jalan. Bisa test 1 RF dulu.
            if isi ~= lastIsi then
                lastIsi = isi
                warn("UPDATE-WORKER dari panel -> cek versi GitHub + restart sesi")
                pcall(tulis_launcher_loop)   -- pastiin launcher loop dulu
                local naik, vBaru = cek_worker_versi(cfg)
                if naik then
                    lapor(cfg, "UPDATE-WORKER", cacheRun)
                    info("[update] worker -> v" .. tostring(vBaru) .. ", restart sesi...")
                    os.execute("sleep 1")
                    os.exit(0)   -- launcher loop jalanin worker baru
                else
                    ok("[update] worker udah versi terbaru (v" .. VERSION .. ") atau gagal cek")
                    lapor(cfg, isi, cacheRun); lastStatus = os.time()
                end
            end
            skip_sisa = true
        elseif U:find("DOWNLOAD%-APK") then
            -- v9.107: DOWNLOAD-APK:<file1>|<file2>|... dari panel -> download+install
            -- SEMUA file yg dicentang (Delta client + VPN + Termux:Boot) sekaligus.
            if isi ~= lastIsi then
                lastIsi = isi
                local daftar = isi:match("DOWNLOAD%-APK:(.+)$") or ""
                local files = {}
                for nm in daftar:gmatch("[^|]+") do
                    nm = nm:gsub("^%s+", ""):gsub("%s+$", "")
                    if nm ~= "" then files[#files+1] = nm end
                end
                warn(("DOWNLOAD-APK dari panel: %d file"):format(#files))
                local sk, gg = 0, 0
                for _, nm in ipairs(files) do
                    local ok2 = false
                    pcall(function() ok2 = download_apk_url(cfg, nm, nm) end)
                    if ok2 then sk = sk + 1 else gg = gg + 1 end
                end
                ok(("DOWNLOAD-APK selesai: %d pasang, %d gagal"):format(sk, gg))
                lapor(cfg, isi, cacheRun); lastStatus = os.time()
            end
            skip_sisa = true
        elseif U:find("DOWNLOAD%-DELTA") then
            -- v9.103: DOWNLOAD-DELTA:19,20 dari panel -> download+install client slot
            -- tsb doang (checklist panel). Format "DOWNLOAD-DELTA:19,20".
            if isi ~= lastIsi then
                lastIsi = isi
                local slotStr = isi:match("DOWNLOAD%-DELTA:([%d,]+)") or ""
                warn("DOWNLOAD-DELTA dari panel -> slot: " .. (slotStr ~= "" and slotStr or "(kosong)"))
                if slotStr ~= "" then
                    local ver = cek_delta_versi(cfg) or "2.731.944"
                    pcall(function() download_delta_slot(cfg, slotStr, ver) end)
                    ok("DOWNLOAD-DELTA slot selesai: " .. slotStr)
                else
                    err("[download-slot] format salah, harusnya DOWNLOAD-DELTA:19,20")
                end
                lapor(cfg, isi, cacheRun); lastStatus = os.time()
            end
            skip_sisa = true
        elseif U:find("UPDATE%-DELTA") or U:find("UPDATEDELTA") then
            -- v9.100: UPDATE-DELTA dari panel -> cek delta_versi.txt + update SEMUA
            -- client ke versi terbaru (manual trigger, gak nunggu 10 menit).
            if isi ~= lastIsi then
                lastIsi = isi
                warn("UPDATE-DELTA dari panel -> cek versi + update semua client")
                local target = cek_delta_versi(cfg)
                if target and target ~= "" then
                    info(("[delta] target versi: v%s -> update semua client"):format(target))
                    pcall(function() update_delta_ke(cfg, target) end)
                    ok("UPDATE-DELTA selesai ke v" .. target)
                    notify("Velium "..cfg.tim, "Delta diupdate ke v"..target)
                else
                    err("[delta] gak bisa baca delta_versi.txt di GitHub")
                end
                DELTA_CEK_TS = os.time()   -- reset timer auto-cek
                lapor(cfg, isi, cacheRun); lastStatus = os.time()
            end
            skip_sisa = true
        elseif U:find("CLOSE") then
            -- v9.77: CLOSE = tutup semua client (worker tetep jalan). Handler
            -- TERPISAH -- dulu nyasar di blok RESTART (bikin RESTART bekas ke-CLOSE
            -- -> tutup 10 client liar). Sekarang cuma jalan kalau isi BENERAN CLOSE.
            -- v9.278: CLOSE:daftar -> tutup CUMA client di daftar (buat pindah server
            -- per-tim: force-stop client target biar FORCE buka ulang di server baru,
            -- tim lain gak keganggu). CLOSE polos -> tutup semua (perilaku lama).
            if isi ~= lastIsi then
                lastIsi = isi
                local daftarC = isi:match("CLOSE:([%w%.%_%-,]+)")
                if daftarC then
                    local onlyC = {}
                    for a in daftarC:gmatch("[^,]+") do onlyC[a] = true end
                    local pkgsC = {}
                    for _, pkg in ipairs(split(cfg.pkgs)) do
                        local u = (mapAkun or {})[pkg]
                        local nm = pkg:gsub("com%.roblox%.", "")
                        if onlyC[u] or onlyC[pkg] or onlyC[nm] then pkgsC[#pkgsC+1] = pkg end
                    end
                    if #pkgsC > 0 then
                        -- v9.285: CLOSE:daftar = TUTUP target BARENGAN doang (paralel,
                        -- cepet). Batch-reopen (v9.282-284) dibuang -- bikin "0 jalan"
                        -- (open_all skip/return dini) + CLOSE udah gak dipake 2-tim
                        -- (2-tim=RESTART, per-tim=TEMBAK). CLOSE murni buat tutup.
                        warn("CLOSE daftar dari panel -> tutup " .. #pkgsC .. " client BARENGAN (target aja)")
                        local cmd = "su -c '"
                        for _, pk in ipairs(pkgsC) do cmd = cmd .. "am force-stop " .. pk .. " & " end
                        cmd = cmd .. "wait'"
                        sh_silent(cmd)
                        os.execute("sleep 2")
                        -- v9.290: SET grace (tembak_ts) semua yg ditutup -> denyut-rejoin
                        -- ke-BLOCK. Bug user: abis CLOSE, denyut-rejoin buka client duluan
                        -- (1-1 lambat), terus FORCE buka LAGI = DOBEL out-in. Grace bikin
                        -- denyut-rejoin diem -> FORCE (dari panel, 8s nyusul) yg buka batch
                        -- -> gak dobel. Grace 240s > 8s jeda CLOSE->FORCE, aman.
                        local tNowC = os.time()
                        for _, pk in ipairs(pkgsC) do KICK_DIURUS["tembak_ts:" .. pk] = tNowC end
                        ok("CLOSE: " .. #pkgsC .. " client target ditutup (barengan) -> denyut-rejoin di-BLOCK, tunggu FORCE")
                        notify("Velium "..cfg.tim, "CLOSE -> "..#pkgsC.." client target ditutup")
                    else
                        warn("CLOSE daftar tapi 0 match -> gak nutup apa2 (cek nama akun)")
                    end
                else
                    warn("CLOSE dari panel -> tutup semua client")
                    local n = close_all(cfg)
                    ok("CLOSE: " .. n .. " client ditutup")
                    notify("Velium "..cfg.tim, "CLOSE -> "..n.." client ditutup")
                end
                lapor(cfg, isi, cacheRun)
                lastStatus = os.time()
            end
            skip_sisa = true
        elseif U:find("TEMBAK") then
            -- v9.281: TEMBAK:daftar = tembak ulang client target ke server BARU TANPA
            -- close (am start -S -d URL, cuma restart ACTIVITY, app+service tetep idup).
            -- User: "jalankan salah satu tim -> LANGSUNG TEMBAK aja, gakmau di-close".
            -- Beda dari REJOIN (close+open) & CLOSE (tutup). Ini murni open_one (tembak)
            -- ke server baru buat client target, walau lagi jalan -> Roblox teleport.
            if isi ~= lastIsi then
                lastIsi = isi
                local daftarT = isi:match("TEMBAK:([%w%.%_%-,]+)")
                if daftarT then
                    local onlyT = {}
                    for a in daftarT:gmatch("[^,]+") do onlyT[a] = true end
                    local pkgsT = {}
                    for _, pkg in ipairs(split(cfg.pkgs)) do
                        local u = (mapAkun or {})[pkg]
                        local nm = pkg:gsub("com%.roblox%.", "")
                        if onlyT[u] or onlyT[pkg] or onlyT[nm] then pkgsT[#pkgsT+1] = pkg end
                    end
                    if #pkgsT > 0 then
                        refresh_ps(); pcall(refresh_ps_getps)   -- server baru ke-refresh dulu
                        warn(("TEMBAK dari panel -> tembak ulang %d client ke server baru (TANPA close)"):format(#pkgsT))
                        for i, pkg in ipairs(pkgsT) do
                            KICK_DIURUS["tembak_ts:" .. pkg] = os.time()   -- grace (baru ditembak)
                            open_one(cfg, pkg, mapLink[pkg], "tembak-panel", true)   -- arceus -> dipaksa WC
                            -- v9.289: 1x per client + jeda 30s antar client (user minta
                            -- 1x cukup). Arceus = 30; lain = stagger_sec.
                            if i < #pkgsT then
                                local jedaT = (cfg.executor == "arceus") and 30 or (cfg.stagger_sec or 8)
                                for _ = 1, jedaT do
                                    if ada_stop() then break end
                                    os.execute("sleep 1")
                                end
                            end
                        end
                        ok(("TEMBAK: %d client ditembak ke server baru (langsung, tanpa close)"):format(#pkgsT))
                        notify("Velium "..cfg.tim, "TEMBAK -> "..#pkgsT.." client ke server baru")
                        lastOpen = os.time()
                    else
                        warn("TEMBAK daftar tapi 0 match -> gak nembak apa2 (cek nama akun)")
                    end
                end
                lapor(cfg, isi, cacheRun)
                lastStatus = os.time()
            end
            skip_sisa = true
        elseif U:find("RESTART") then
            -- v9.01: RESTART = tutup SEMUA client -> buka fresh dari nol (setting
            -- baru kepakai bersih). Logic dipindah ke fungsi GLOBAL restart_kerjakan
            -- biar lokal-nya gak masuk hitungan run(cfg) (batas 200 lokal).
            -- v9.41: bedain RESTART pakai TS (bukan isi). Bug user: netralin ke
            -- FORCE bikin bingung "kalau mau ganti setting gimana". Sekarang: RESTART
            -- keproses kalau TS BARU (tiap pencet Start = ts naik). RESTART yg SAMA
            -- (ts sama, bekas di DB) -> gak keproses (anti-loop). Restart kapan aja
            -- bisa (pencet Start / ganti setting = ts baru), loop dicegah via ts.
            local tsRestart = ambil_num(respTop, "ts") or 0
            if tsRestart ~= (lastRestartTs or 0) then
                lastRestartTs = tsRestart
                RESTART_TS_PROSES = tsRestart   -- v9.77: tandai ts ini udah diproses
                lastIsi = isi
                MODE_JALAN = true
                SUDAH_GRID = false; GRID_CACHE = nil
                PKGS_AKTIF = restart_kerjakan(cfg, isi, mapAkun, mapLink, ada_stop)
                if PKGS_AKTIF and #PKGS_AKTIF > 0 then simpan_aktif(cfg) end   -- v9.89: simpen state
                refresh_status(); lastStatusCek = os.time()
                lapor(cfg, isi, cacheRun); lastStatus = os.time()
                info("RESTART selesai (ts=" .. tsRestart .. ") -- lanjut buka client")
                -- v9.65: kirim FORCE:daftar ke DB sendiri biar pasti buka client
                -- (gak tergantung backend expire RESTART->FORCE).
                do
                    local daftarForce = isi:match("RESTART:(.+)")
                    local isiForce = daftarForce and ("FORCE:" .. daftarForce) or force_str(cfg, mapAkun)
                    lastIsi = isiForce
                    pcall(function()
                        tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":"%s"}', jstr(cfg.tim), isiForce))
                    end)
                    info("RESTART -> FORCE dikirim (client bakal kebuka)")
                    _apb_waktu = 0   -- reset cek perintah (fresh ronde depan)
                end
                skip_sisa = true   -- ronde ini skip (baru tutup+grid), ronde depan FORCE buka
            else
                -- v9.79: RESTART bekas (ts SAMA, udah diproses) -> JANGAN skip_sisa.
                -- Bug: skip_sisa=true di sini -> denyut rejoin gak jalan -> client
                -- gak kebuka -> "0/6 di game" loop selamanya. Sekarang: biarin loop
                -- antrian/denyut jalan buka client. + kirim ulang FORCE ke DB biar
                -- RESTART bekas keganti (gak ke-detect terus).
                local daftarForce = isi:match("RESTART:(.+)")
                local isiForce = daftarForce and ("FORCE:" .. daftarForce) or force_str(cfg, mapAkun)
                if lastIsi ~= isiForce then
                    lastIsi = isiForce
                    pcall(function()
                        tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":"%s"}', jstr(cfg.tim), isiForce))
                    end)
                    info("RESTART bekas (ts=" .. tsRestart .. ", udah diproses) -> kirim FORCE, lanjut buka client")
                end
            end
            -- v9.64: RESTART nyangkut (ts sama, udah diproses) -> JANGAN skip_sisa ->
            -- biarin loop antrian buka client. Dulu skip_sisa=true di luar if -> loop
            -- antrian gak jalan -> client kebuka cuma kalau backend expire RESTART->
            -- FORCE. Sekarang gak tergantung backend (worker sendiri buka).
            -- v9.77: blok CLOSE yg dulu di sini (isi~=lastIsi -> close_all) DIBUANG --
            -- itu bikin RESTART bekas (isi=RESTART, lastIsi=FORCE) nutup 10 client
            -- liar. CLOSE sekarang handler sendiri di atas.
            -- v9.79: skip_sisa DIBUANG dari sini -> RESTART bekas biarin denyut rejoin
            -- jalan (buka client). skip_sisa cuma pas RESTART BARU keproses (di atas).
        end

        if not skip_sisa then

        -- KILL dari panel: beda sama STANDBY.
        -- STANDBY = berhenti buka client, worker tetep jalan.
        -- KILL    = worker-nya sendiri yang mati.
        if isi:upper():find("KILL") then
            warn("KILL dari panel")
            lapor(cfg, "MATI")   -- kabarin panel dulu, biar gak nunggu 7 menit
            bersih(cfg, "KILL dari panel")
            return
        end

        if isi ~= lastIsi and isi ~= "" then
            info("perintah baru: " .. isi)
            -- v7.99: PLACE:<id> dari panel -> ganti place_id (pindah world/map).
            -- Fill server = pindah ke world baru (129343810645058). build_url pakai
            -- place_id baru -> client join world baru. Simpen ke config biar tetep.
            local placeBaruDari = isi:match("PLACE:(%d+)")
            if placeBaruDari then
                cfg.place_id = placeBaruDari
                pcall(function() save_config(cfg) end)
                info("Place diganti ke " .. placeBaruDari .. " (pindah world) -- rejoin buat masuk")
                SUDAH_GRID = false; GRID_CACHE = nil
            end
            -- v8.57: GRID:<kolom> dari panel -> atur jumlah kolom grid manual.
            -- GRID:0 / GRID:auto -> balik otomatis (SUSUNAN). Reset grid biar
            -- ke-nata ulang pakai kolom baru.
            -- v8.58: FORCE-STOP client dulu. Grid cuma kepakai pas client dibuka
            -- FRESH (prefs dibaca App Cloner saat buka). Kalau client udah jalan,
            -- posisi lama (di memori) tetep kepakai -> bug bekas lama. Tutup semua
            -- -> denyut rejoin buka ulang dgn prefs grid baru.
            local gridDari = isi:match("GRID:(%w+)")
            if gridDari then
                local k = tonumber(gridDari)
                cfg.grid_kolom = (k and k >= 1) and k or 0
                pcall(function() save_config(cfg) end)
                SUDAH_GRID = false; GRID_CACHE = nil
                -- v8.60: kalau lagi STANDBY (belum Start), JANGAN tutup/buka client.
                -- Cuma SIMPEN setelan grid -> kepakai pas Start nanti. User minta:
                -- set grid pas standby = client tetep ketutup, gak kebuka sendiri.
                local lagiStandby = isi:upper():find("STANDBY") ~= nil
                    or (not isi:upper():find("FORCE") and not isi:upper():find("REJOIN"))
                if lagiStandby then
                    info("Grid diset " .. (cfg.grid_kolom > 0 and (cfg.grid_kolom .. " kolom") or "otomatis")
                         .. " (STANDBY -- disimpen, kepakai pas Start)")
                else
                    -- lagi jalan -> tutup cepet + buka ulang dgn grid baru
                    local ditutup = 0
                    pcall(function() ditutup = close_all_cepat(cfg, true) end)
                    info("Grid diatur: " .. (cfg.grid_kolom > 0 and (cfg.grid_kolom .. " kolom") or "otomatis")
                         .. " -- " .. tostring(ditutup) .. " client ditutup, buka ulang dgn grid baru")
                end
            end
            -- v7.03: FORCE dari panel = MULAI FRESH kayak worker baru. Reset
            -- SUDAH_GRID (nata tempat/tiling ULANG) + lastOpen (buka client dari
            -- 1/8 lagi). User minta: pencet Start/FORCE -> ngulang semua dari awal
            -- (nata grid, buka client dari awal). Cuma pas TRANSISI ke FORCE
            -- (dari standby/perintah lain), bukan tiap ronde FORCE.
            local isiBaruU = isi:upper()
            local lastU = (lastIsi or ""):upper()
            local jadiForce = isiBaruU:find("FORCE") and not lastU:find("FORCE")
            if jadiForce then
                info("FORCE dari panel -- mulai fresh (nata tempat + buka client dari awal)")
                SUDAH_GRID = false   -- nata grid/tiling ulang
                GRID_CACHE = nil     -- v7.61: hitung grid fresh sesi baru
                lastOpen = 0         -- buka client dari 1/8 lagi (gak nunggu reopen_sec)
                -- v9.274: ARCEUS -> pas FORCE (mulai fresh), TUTUP semua client + buang
                -- task + matiin freeform-sistem DULU, baru boot buka ulang fresh. Biar
                -- gak ada sisa BINGKAI DOBEL dari sesi lalu (freeform nyangkut di task/
                -- client lama). User minta: start paksa = close semua + hapus freeform
                -- double dulu. Cuma Arceus (Delta gak kena masalah ini).
                -- v9.275: HAPUS force-stop-semua. Dulu (v9.274) pas FORCE Arceus
                -- worker tutup SEMUA client + buang task, buat ngejar "bingkai dobel".
                -- TAPI ternyata double-frame itu ARTEFAK TES (buka pakai am start TANPA
                -- -S = double; worker pakai `am start -S` = 1 bingkai, aman). Jadi
                -- bersih-bersih paksa GAK PERLU + malah nutup client yg lagi jalan
                -- (user: "pas jalankan malah force close semua, harusnya tembak doang").
                -- Sekarang FORCE = tembak client yg dipilih doang (open_all natural),
                -- gak nutup semua. Freeform setting tetep dimatiin (murah, gak nutup client).
                if cfg.executor == "arceus" then
                    sh_silent("su -c 'settings put global enable_freeform_support 0; settings put global force_resizable_activities 0;'")
                end
                -- v9.277: BLOKIR denyut-rejoin selama proses START PAKSA. Bug user: pas
                -- FORCE, worker lagi sibuk BUKA client, tapi denyut-cek jalan barengan +
                -- rejoin client yg denyutnya masih lama (baru ditutup, belum sempet nulis
                -- denyut baru) -> FORCE + rejoin BENTROK. User minta: pas start paksa,
                -- FOKUS buka client dulu, denyut-cek di-BLOCK, baru cek ulang 3 menit
                -- SETELAH client masuk. Caranya: set grace (tembak_ts) buat SEMUA client
                -- target FORCE DARI SEKARANG (bukan nunggu kebuka). Grace 240s nutup
                -- proses buka + boot; pas tiap client beneran kebuka, tembak_ts di-refresh
                -- lagi (8075) -> grace lanjut 3-4 menit dari kebuka. Jadi gak ke-rejoin
                -- selama FORCE + 3 menit setelah masuk.
                do
                    local daftarF = isi:match("FORCE:([%w%.%_,]+)")
                    local targetF = {}
                    if daftarF then
                        for nm in daftarF:gmatch("[^,]+") do targetF[nm:lower()] = true end
                    end
                    local tNow = os.time()
                    for _, pk in ipairs(split(cfg.pkgs or "")) do
                        -- FORCE polos (tanpa daftar) = semua; FORCE:daftar = cuma yg didaftar
                        local akun = (mapAkun and mapAkun[pk] or ""):lower()
                        local pkShort = pk:gsub("com%.roblox%.", ""):lower()
                        if not daftarF or targetF[akun] or targetF[pkShort] then
                            KICK_DIURUS["tembak_ts:" .. pk] = tNow
                        end
                    end
                    info("START PAKSA: denyut-rejoin di-BLOCK (grace) -- fokus buka client dulu, cek denyut lagi setelah masuk")
                end
            end
            lastIsi = isi
        end

        -- v9.81: UPDATE lewat REBOOT. Tarik worker terbaru (skrip `up`) -> reboot
        -- RF -> worker versi BARU auto-jalan abis nyala (via Termux:Boot). User:
        -- update = reboot aja, biar gak perlu FORCE manual + pasti fresh.
        if isi:upper():find("^UPDATE") then
            -- v9.83: update lewat reboot -> cek boot siap dulu (cegah brick RF)
            local siapU, alasanU = boot_siap()
            if not siapU then
                warn("UPDATE DIBATALIN -- " .. alasanU .. " (reboot bakal matiin RF)")
                tambahLog("UPDATE batal: " .. alasanU)
                notify("Velium "..cfg.tim, "UPDATE batal: " .. alasanU)
                pcall(function()
                    tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":%s}', jstr(cfg.tim), jstr(force_str(cfg, mapAkun))))
                end)
                lapor(cfg, "UPDATE-BATAL", cacheRun)
            else
            info("UPDATE dari panel -- tarik worker terbaru (proses TERPISAH), terus REBOOT RF")
            local PFX = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
            local HOME = os.getenv("HOME") or "/data/data/com.termux/files/home"
            -- reset perintah + lapor DULU, selagi worker MASIH IDUP (biar kekirim).
            -- Kalau nunggu updater, worker udah mati -> gak kekirim.
            pcall(function()
                tulis_perintah_jaga(cfg, string.format('{"tim":%s,"isi":%s}', jstr(cfg.tim), jstr(force_str(cfg, mapAkun))))
            end)
            lapor(cfg, "UPDATE", cacheRun)
            tambahLog("UPDATE: tarik worker baru (terpisah) -> reboot")
            notify("Velium "..cfg.tim, "update -> reboot, worker baru abis nyala")
            -- v9.87 FIX 'Killed': DULU worker jalanin `up` LANGSUNG. `up` bunuh worker
            -- (velium stop) -> `up` (ANAK worker) ikut ke-KILL sebelum sempet reboot ->
            -- worker keupdate tapi GAK reboot. FIX: tulis skrip updater TERPISAH,
            -- jalanin DETACHED (setsid) -> lepas dari proses worker. Worker exit,
            -- updater lanjut sendiri di sesi lain: download -> reboot. Gak ke-kill.
            local upd = HOME .. "/.velium_update_now.sh"
            local f = io.open(upd, "w")
            if f then
                f:write(table.concat({
                    "#!" .. PFX .. "/bin/sh",
                    "sleep 2",
                    "velium stop >/dev/null 2>&1",
                    'URL="' .. REPO_WORKER .. '/velium_worker.lua?v=$(date +%s)"',
                    'if curl --version >/dev/null 2>&1; then',
                    '  curl -fsSL -H "Cache-Control: no-cache" -H "Pragma: no-cache" "$URL" -o "$HOME/velium_worker.baru"',
                    'else',
                    '  wget -q --no-cache -O "$HOME/velium_worker.baru" "$URL"',
                    'fi',
                    'if head -5 "$HOME/velium_worker.baru" 2>/dev/null | grep -q "VELIUM WORKER"; then',
                    '  mv "$HOME/velium_worker.baru" "$HOME/velium_worker.lua"',
                    '  echo "OK $(grep -m1 \'local VERSION\' "$HOME/velium_worker.lua")" > "$HOME/.velium_update.hasil"',
                    'else',
                    '  echo "GAGAL download (belum di-push?)" > "$HOME/.velium_update.hasil"',
                    'fi',
                    "sleep 1",
                    -- reboot: beberapa cara, salah satu pasti jalan
                    "su -c reboot >/dev/null 2>&1",
                    "su -c 'svc power reboot' >/dev/null 2>&1",
                    "sleep 8",
                    "su -c reboot >/dev/null 2>&1",
                    "",
                }, "\n"))
                f:close()
                os.execute("chmod +x " .. upd)
            end
            -- lepas DETACHED: setsid (sesi baru) + nohup + & -> gak mati sama worker.
            os.execute("setsid nohup sh " .. upd .. " </dev/null >" .. HOME .. "/.velium_update.log 2>&1 &")
            ok("Updater dilepas (terpisah) -- worker berhenti, RF reboot bentar lagi")
            os.execute("sleep 1")
            os.exit(0)
            end
        end

        -- v5.99: CEKCOOKIE dari panel. Panel kirim "CEKCOOKIE" ke tim ini ->
        -- worker cek cookie SEMUA akun yang lagi login di client-nya (hidup/
        -- mati/captcha/ban), setor status ke panel. Aksi sekali, balik FORCE.
        if isi:upper():find("^CEKCOOKIE") then
            info("CEKCOOKIE dari panel -- cek cookie semua akun tim ini")
            os.execute(((os.getenv("PREFIX") or "/data/data/com.termux/files/usr")
                .. "/bin/velium") .. " cekcookie")
            pcall(function()
                -- v9.46: FORCE dgn DAFTAR (dari PKGS_AKTIF) biar gak buka semua 10
                local isiBalik = "FORCE"
                if PKGS_AKTIF and #PKGS_AKTIF > 0 then
                    local akunAktif = {}
                    for _, pkg in ipairs(PKGS_AKTIF) do
                        local u = mapAkun[pkg]
                        if u and tostring(u) ~= "" then akunAktif[#akunAktif+1] = u end
                    end
                    if #akunAktif > 0 then isiBalik = "FORCE:" .. table.concat(akunAktif, ",") end
                end
                api_post(cfg, "/perintah", string.format('{"tim":%s,"isi":"%s"}', jstr(cfg.tim), isiBalik), "PUT")
            end)
            lastIsi = "FORCE"
            skip_sisa = true
        end

        -- Perintah kesimpen di DB, jadi isinya = keadaannya.
        -- Gak perlu forceSticky kayak jaman ntfy (pesan kedaluwarsa).
        -- v6.84: `mati` udah didefinisi di atas (sebelum cek lisensi).
        -- v6.82: FORCE itu perintah UNIVERSAL -- worker APA PUN jalan pas FORCE,
        -- gak peduli cfg.targets. Dulu hit CUMA is_target(isi, targets) -> kalau
        -- targets worker beda dari kata di perintah, FORCE gak "hit" -> worker
        -- gak buka client (walau di-start dari panel). STOP jalan (dicek
        -- terpisah). Sekarang: FORCE / REJOIN / target-match -> semua bikin hit.
        local isiU = isi:upper()
        local hit  = (not mati) and (
            isiU:find("FORCE") ~= nil or
            isiU:find("REJOIN") ~= nil or
            is_target(isi, cfg.targets)
        )

        -- v4.24: status dasar buat panel (nanti ditimpa aksi spesifik kalau lagi kerja)
        if mati then
            setAksi("standby â€” gak buka client")
            -- v7.04: STOP (bukan STANDBY biasa) = STANDBY + KILL ALL client. User
            -- minta: pencet Stop -> langsung tutup semua client (balik awal/kosong),
            -- pas Force lagi mulai fresh. Cuma SEKALI pas transisi ke STOP (penanda
            -- stop_killed) biar gak kill tiap ronde. STANDBY biasa gak kill (client
            -- dibiarin, cuma gak buka baru).
            local isiStop = isi:upper():find("STOP")
            if isiStop and not KICK_DIURUS["stop_killed"] then
                warn("STOP dari panel -> tutup SEMUA client BARENGAN (cepet)")
                local n = close_all_cepat(cfg)
                ok("STOP: " .. n .. " client ditutup. Pencet Start buat mulai fresh.")
                KICK_DIURUS["stop_killed"] = true
                SUDAH_GRID = false
                lastOpen = 0
            end
            -- v6.87: pas STANDBY, CLEAR offlama + diag semua client. "off X menit"
            -- cuma valid pas udah FORCE (client harusnya jalan). Pas standby (user
            -- sengaja belum start), client off itu WAJAR -> jangan hitung/tampilin
            -- "off X menit" di panel, jangan diagnosa. Reset biar bersih.
            for _, pStd in ipairs(split(cfg.pkgs or "")) do
                KICK_DIURUS["offlama:" .. pStd] = nil
                KICK_DIURUS["diag:" .. pStd] = nil
            end
        else
            -- v7.04: keluar dari STOP/STANDBY (lagi FORCE) -> reset penanda
            -- stop_killed biar STOP berikutnya kill lagi.
            KICK_DIURUS["stop_killed"] = nil
            local nJalan = 0
            for _, p in ipairs(split(cfg.pkgs)) do if cacheRun[p] then nJalan = nJalan + 1 end end
            setAksi(string.format("mantau %d/%d client jalan", nJalan, #split(cfg.pkgs)))
        end

        -- ============================================================
        -- v5.02: BYPASS KEY OTOMATIS -- dikerjain SAMPAI KELAR, yang lain nunggu.
        --
        -- Kenapa harus eksklusif: nyari tombol itu butuh jendela client di depan
        -- + baca papan klip (yang butuh Termux di depan sebentar). Kalau barengan
        -- sama jaga-jendela / buka client / auto-rejoin, fokusnya kerebut terus
        -- dan urutan tap-nya kacau. Karena Lua di sini jalan satu-satu, blok ini
        -- otomatis nahan yang lain selama dia jalan.
        --
        -- CUKUP SATU CLIENT: berkas lisensinya di /sdcard, dipakai BARENG semua
        -- client. Sekali ketulis, clienu sampai clienz kebagian -- gak usah
        -- diulang per client.
        -- ============================================================
        -- ============================================================
        -- v5.48: BLOK BYPASS DI LOOP UTAMA DIBUANG.
        --
        -- Dia TABRAKAN sama cek lisensi yang ada di open_all (v5.46/5.47):
        --   1. blok ini jalan DULUAN dalam satu putaran, nyetel BYPASS_TERAKHIR
        --   2. open_all dipanggil setelahnya -> cek di dalamnya kena cooldown
        --      5 menit -> DILEWAT
        --   3. jadi 4 client kebuka semua tanpa bypass, nyangkut di layar key
        --
        -- Dan blok ini sendiri cacat: dia milih client buat nyari tombol TAPI
        -- GAK MEMBUKANYA. Pas worker baru nyala, gak ada client yang jalan ->
        -- nyari tombol di layar kosong -> pasti gagal.
        --
        -- Yang di open_all bener: dia BUKA client-nya dulu, tungguin layar
        -- key-nya nongol, baru nyari tombol. Dan open_all dipanggil berkala
        -- (tiap reopen_sec), jadi lisensi yang abis di tengah sesi tetep
        -- ketangkep -- gak perlu jaring kedua di sini.
        -- ============================================================
        local lewatiRonde = false

        if not lewatiRonde then   -- v5.02: ronde bypass gak ngerjain yang lain

        -- v4.46: CLIENT MATI MENDADAK (ditutup manual / di-swipe / crash).
        -- Dulu nunggu siklus reopen_sec (5 MENIT) baru kebuka lagi. Sekarang
        -- ketahuan dalam ~10 detik: banding status ronde ini sama ronde lalu.
        -- Cuma pas FORCE aktif -- kalau STANDBY/CLOSE ya emang sengaja ditutup.
        if false then  -- v7.49: mati-bareng DIMATIIN (ganti loop grafis)
            -- v7.13: kumpulin SEMUA yang mati mendadak DULU, baru putusin cara buka.
            local matiBareng = {}
            for _, pkg in ipairs(split(cfg.pkgs)) do
                -- v9.122: rotasi_on -> tim 2 dilewat (standby, jangan masuk mati-bareng)
                if runSebelum[pkg] == true and cacheRun[pkg] == false and not rotasi_lewat(cfg, pkg) then
                    matiBareng[#matiBareng+1] = pkg
                end
            end
            if #matiBareng >= 3 then
                -- v7.42: BANYAK mati bareng -> masukin SATU-SATU, PASTIIN MASUK
                -- dulu (cek grafis) baru lanjut client berikutnya. JANGAN tembak
                -- bareng (RAM lonjak/Delta keteteran). Tiap client: tembak -> cek
                -- grafis 20s -> masuk? lanjut : tembak lagi (maks 3x) -> skip kalau
                -- gak masuk (ketangkep ronde berikutnya).
                tambahLog(("MATI BARENGAN: %d client keluar -> masukin SATU-SATU (pastiin masuk dulu)"):format(#matiBareng))
                for _, pkg in ipairs(matiBareng) do
                    -- skip captcha/ban
                    local akM = mapAkun[pkg]
                    if KICK_DIURUS["captcha:" .. pkg] or (akM and KICK_DIURUS["mati:" .. akM]) then
                        tambahLog("  skip " .. (akM or pkg:gsub("com%.roblox%.","")) .. " (captcha/ban)")
                    else
                        local masuk = false
                        for coba = 1, 3 do
                            RIW.catat("REJOIN", akM or pkg, "karena=mati-bareng")
                            -- v7.47: kalau hidup+nyangkut, force-stop dulu (am
                            -- start no-op ke app hidup). Cuma client ini.
                            -- v7.84: force-stop DIHAPUS (user minta). open_one
                            -- cara Pandora (P/A3) re-join tanpa kill.
                            open_one(cfg, pkg, mapLink[pkg], "mati-bareng")
                            jaga_depan(cfg, mapLink)
                            refresh_status(); gambar_tabel(isi)
                            -- cek standby di tengah (interupsi)
                            local pNow = ambil_str(api_get(cfg, "/perintah?tim=" .. cfg.tim), "isi") or ""
                            if pNow:upper():find("STANDBY") or pNow:upper():find("STOP") then break end
                            -- PASTIIN MASUK: cek grafis 30s (log MB pas masuk)
                            local masukG, mbG = cek_masuk_game(pkg, 30, cek_batal)
                            if masukG then
                                masuk = true
                                tambahLog(("  %s MASUK GAME (grafis %.0f MB, percobaan %d)"):format(
                                    akM or pkg:gsub("com%.roblox%.",""), mbG or 0, coba))
                                break
                            else
                                tambahLog(("  %s belum masuk (grafis %.0f MB, percobaan %d/3), tembak lagi"):format(
                                    akM or pkg:gsub("com%.roblox%.",""), mbG or 0, coba))
                            end
                        end
                        if not masuk then
                            tambahLog("  " .. (akM or pkg:gsub("com%.roblox%.","")) .. " gagal 3x -> skip (coba ronde berikutnya)")
                        end
                        refresh_status(); gambar_tabel(isi)
                    end
                end
                lastStatusCek = os.time()
            else
                -- sedikit (1-2) -> buka satu-satu kayak biasa (aman)
                for _, pkg in ipairs(matiBareng) do
                    tambahLog("MATI MENDADAK: " .. (mapAkun[pkg] or pkg:gsub("com%.roblox%.",""))
                              .. " -> dibuka lagi")
                    RIW.catat("REJOIN", mapAkun[pkg] or pkg, "karena=mati-mendadak")
                    setAksi("buka lagi " .. (mapAkun[pkg] or pkg:gsub("com%.roblox%.","")))
                    open_one(cfg, pkg, mapLink[pkg], "mati-mendadak")
                    os.execute("sleep 3")
                    refresh_status(); lastStatusCek = os.time()
                    gambar_tabel(isi)
                end
            end
        end
        for _, pkg in ipairs(split(cfg.pkgs)) do runSebelum[pkg] = cacheRun[pkg] end

        -- v6.21: NYANGKUT DI HOME (grafis < 30MB) -> SEGERA MASUKIN, gak nunggu.
        -- User minta lebih agresif: begitu ketauan client nyangkut di Home
        -- (grafis rendah = bukan di game), langsung am start ke game -- gak ada
        -- drama nyangkut lama. BEDA dari "script off" (client MATI/ditutup) --
        -- itu JANGAN dipaksa (mungkin sengaja dimatiin). Cuma yang JALAN tapi
        -- nyangkut di Home yang dimasukin.
        --   grafis >= 30MB = di game (aman, skip)
        --   grafis <  30MB + client jalan = nyangkut Home -> masukin
        --   client MATI (run=false) = script off -> BIARIN (jangan paksa)
        -- Jeda 90s antar cek-grafis per client (grafis_kb ~12s, jangan spam).
        if false then  -- v7.49: nyangkut-home DIMATIIN (ganti loop grafis)
            for _, pkg in ipairs(split(cfg.pkgs)) do
                local akCk = mapAkun[pkg]
                -- v6.24: cookie MATI/BAN -> SKIP TOTAL dari sesi ini. Anggap null.
                -- Gak dicek, gak dicek-grafis, gak direjoin -- worker gak sentuh
                -- sama sekali sampai cookie diperbaiki. Client-nya DIBIARIN (gak
                -- di-kick) -- cuma diabaikan worker. Sekali ditandai mati (di cek
                -- nyangkut / auto-setor), lewati terus.
                if (akCk and KICK_DIURUS["mati:" .. akCk]) or rotasi_lewat(cfg, pkg) then
                    -- lewati -- akun ini dianggap gak ada sampai cookie beres
                    -- v9.122: ATAU tim 2 pas rotasi (standby, jangan disentuh)
                else
                -- cuma cek client yang JALAN tapi script gak lapor. Yang MATI
                -- (script off) dilewat -- sesuai permintaan user.
                local jalanTapiDiem = (cacheRun[pkg] == true and cacheBridge[pkg] == false
                                       and mapAkun[pkg]) and true or false
                if jalanTapiDiem then
                    -- v7.18: jeda cek grafis 90 detik -- BARENGIN sama dump
                    -- (cek captcha/error juga 90s). User minta: cek home jangan
                    -- terpisah 30s, gabung 90s bareng dump. Satu siklus cek.
                    if (now - (bekuSejak[pkg] or 0)) >= 90 then
                        bekuSejak[pkg] = now
                        local g = grafis_kb(pkg) or 0
                        if g < 30 * 1024 then
                            -- NYANGKUT DI HOME. v6.23: CEK COOKIE DULU sebelum rejoin.
                            -- Kalau cookie BAN/MATI -> percuma rejoin (bakal nyangkut
                            -- lagi). Cuma rejoin kalau cookie HIDUP. Cek dulu, baru
                            -- mutusin -- hemat usaha, gak muter-muter di akun mati.
                            local ak = mapAkun[pkg]
                            local namaP = ak or pkg:gsub("com%.roblox%.","")
                            -- baca cookie via SQL client ini
                            local SQ = "/data/data/com.termux/files/usr/bin/sqlite3"
                            local dbc = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
                            local hC = io.popen(("su -c %s 2>/dev/null"):format(shq(
                                SQ .. " " .. dbc ..
                                " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
                            local ck = hC and hC:read("*all") or ""
                            if hC then hC:close() end
                            ck = cookie_terpanjang(ck or "")

                            local kead = "?"
                            if ck ~= "" and ck:find("_|WARNING") then
                                kead = cek_cookie_roblox(ck)
                                -- setor status ke panel sekalian
                                pcall(function()
                                    api_post(cfg, "/cookie-status", string.format(
                                        '{"akun":%s,"status":%s}', jstr(ak or "?"), jstr(kead)))
                                end)
                            end

                            if kead == "dead" or kead == "ban" then
                                -- cookie mati -> JANGAN rejoin, tandai biar gak dibuka
                                tambahLog("NYANGKUT Home " .. namaP .. " tapi cookie " ..
                                          kead:upper() .. " -> GAK direjoin (perbaiki cookie dulu)")
                                if ak then KICK_DIURUS["mati:" .. ak] = true end
                            else
                                -- v7.41: DUMP CAPTCHA di nyangkut-home DIHAPUS
                                -- (uiautomator lambat). Nyangkut Home (grafis
                                -- rendah) = belum di game -> LANGSUNG rejoin.
                                -- Kalau ternyata captcha, ketangkep jalur diem
                                -- (off >= 5 menit) yang masih dump sekali.
                                tambahLog("NYANGKUT Home (" .. string.format("%.0f", g/1024)
                                          .. "MB): " .. namaP .. " cookie " ..
                                          (kead == "alive" and "ON" or kead) .. " -> masukin game")
                                RIW.catat("REJOIN", ak or pkg, "karena=nyangkut-home")
                                setAksi("masukin " .. namaP)
                                open_one(cfg, pkg, mapLink[pkg], "nyangkut-home")   -- am start, TANPA kill
                                os.execute("sleep 3")
                                refresh_status(); lastStatusCek = os.time()
                                gambar_tabel(isi)
                            end
                        end
                        -- kalau grafis >= 30MB = di game (lagi loading script) -> biarin
                    end
                else
                    bekuSejak[pkg] = nil   -- mati / jalan normal -> reset timer
                end
                end   -- v6.24: tutup blok skip-cookie-mati
            end
        end

        -- v6.92: PASTIIN GANTI AKUN KELAR DULU sebelum open_all. Kalau ada
        -- client dengan target: (pending ganti akun) yang BELUM dikonfirmasi,
        -- JANGAN buka client lain dulu -- tunggu ganti akun beres. User minta:
        -- pas awal FORCE, kalau akun belum dipastiin ganti, jangan lanjut
        -- perintah lain. cek-ganti (di atas) yang mastiin + clear target: pas beres.
        local adaPendingGanti = false
        for _, pkgP in ipairs(split(cfg.pkgs or "")) do
            local pend = pkgP:gsub("com%.roblox%.", "")
            if KICK_DIURUS["target:" .. pend] then
                -- v7.09: TIMEOUT. Kalau ganti akun ketahan > 3 menit (gak pernah
                -- kelar -- misal cookie terenkripsi/client rusak), JANGAN nyangkut
                -- selamanya. Clear target + lapor gagal ke panel, biar client lain
                -- gak ke-blok. Dulu: target gak pernah clear -> "Nunggu ganti akun
                -- kelar" selamanya -> semua client mati nunggu.
                local tgl = KICK_DIURUS["tglganti:" .. pend] or now
                if (now - tgl) > 180 then
                    local akunGagal = KICK_DIURUS["target:" .. pend]
                    tambahLog("GANTI AKUN TIMEOUT: " .. pend .. " (" .. tostring(akunGagal) ..
                        ") gak kelar 3 menit -> nyerah, lanjut. Cek cookie/client (mungkin terenkripsi).")
                    KICK_DIURUS["gantigagal:" .. pend] = akunGagal or "timeout"
                    KICK_DIURUS["target:" .. pend] = nil
                    KICK_DIURUS["cekganti:" .. pend] = nil
                    KICK_DIURUS["tglganti:" .. pend] = nil
                    KICK_DIURUS["retry:" .. pend] = nil
                else
                    adaPendingGanti = true; break
                end
            end
        end
        if hit and adaPendingGanti then
            -- ada ganti akun belum kelar -> tunda open_all, biar cek-ganti kerja dulu
            if (now - (lastPendingLog or 0)) >= 15 then
                info("Nunggu ganti akun kelar dulu sebelum buka client lain...")
                lastPendingLog = now
            end
        end

        -- v6.95: COOLDOWN 3 MENIT. Loop biasa (buka client) cuma jalan kalau udah
        -- 180 detik GAK ADA aktivitas ganti akun. Tiap ada LOGIN, waktuAktivitas
        -- di-reset -> timer mulai lagi. Jadi ganti akun kelar + adem 3 menit dulu,
        -- baru farming. User minta: pisahin loop ganti akun & loop biasa 3 menit.
        local cooldownJalan = (waktuAktivitas == 0) or ((now - waktuAktivitas) >= 180)
        if hit and not adaPendingGanti and not cooldownJalan then
            if (now - (lastCooldownLog or 0)) >= 20 then
                local sisa = 180 - (now - waktuAktivitas)
                info(("Adem dulu %ds abis ganti akun sebelum buka client biasa..."):format(sisa > 0 and sisa or 0))
                lastCooldownLog = now
            end
        end

        if hit and not adaPendingGanti and cooldownJalan then
            -- v8.18: FORCE bisa FORCE:akun1,akun2 -> cuma buka client itu.
            -- FORCE polos = semua. Parse daftar akun (koma) -> set pkg.
            local only = nil
            local daftarAkun = isi:match("FORCE:([%w%.%_,]+)")
            if daftarAkun then
                only = {}
                for ak in daftarAkun:gmatch("[^,]+") do
                    ak = ak:gsub("%s+", "")
                    -- cocokin akun -> pkg (via mapAkun kebalik), atau pkg langsung
                    local ketemu = false
                    for pkg, u in pairs(mapAkun or {}) do
                        if u == ak or pkg == ak or pkg:gsub("com%.roblox%.", "") == ak then
                            only[pkg] = true; ketemu = true
                        end
                    end
                    if not ketemu and ak:find("roblox") then only[ak] = true end
                end
                if not next(only) then only = nil end   -- gak ada yg cocok -> semua
            end
            -- v8.88: simpen daftar client AKTIF (yg dibuka) jadi global -> grid_hitung
            -- pakai JUMLAH INI, bukan semua 10 client. Bug user: pakai 6 client grid
            -- 3 kolom, tapi grid jadi 4x3 (dihitung buat 10 client). Sekarang grid
            -- dihitung buat jumlah client yg beneran dibuka (6 -> 3x2).
            if only then
                -- v9.15: PKGS_AKTIF pakai URUTAN CONFIG (split cfg.pkgs), BUKAN
                -- pairs(only) yg ACAK. Bug user: grid posisi acak, gak mulai dari
                -- kiri atas. pairs() di Lua gak terurut -> PKGS_AKTIF isinya acak ->
                -- grid_hitung kasih posisi ikut urutan acak. Fix: iterasi cfg.pkgs
                -- (urutan 01-10), ambil yg ada di `only` -> urut kiri-atas dulu.
                PKGS_AKTIF = {}
                for _, pkg in ipairs(split(cfg.pkgs)) do
                    -- v9.122: rotasi_on -> PKGS_AKTIF cuma tim 1 (walau only=semua 20).
                    if only[pkg] and not rotasi_lewat(cfg, pkg) then PKGS_AKTIF[#PKGS_AKTIF+1] = pkg end
                end
            else
                -- v9.45: FORCE polos -- kalau PKGS_AKTIF UDAH ada (lagi jalan N
                -- client dari RESTART:daftar sebelumnya), PERTAHANKAN. Bug user:
                -- lagi jalan 6 client, FORCE polos (dari expire/cekcookie) -> buka
                -- SEMUA 10. Cuma reset ke semua kalau PKGS_AKTIF belum ada (fresh).
                if not (PKGS_AKTIF and #PKGS_AKTIF > 0) then
                    PKGS_AKTIF = nil   -- fresh FORCE polos = semua client
                end
                -- kalau PKGS_AKTIF udah ada -> biarin (cuma client itu yg diurus)
            end
            GRID_CACHE = nil   -- client aktif berubah -> grid hitung ulang
            if (now - lastOpen) >= cfg.reopen_sec then
                -- dipanggil di sela-sela client: STANDBY dari panel langsung kebaca,
                -- gak nunggu 10 client kelar dulu
                -- v4.53: catat penanda assign-PS pas MULAI. Kalau berubah di
                -- tengah jalan (panel/suplai mindahin akun), berhenti aja --
                -- instruksi panel lebih penting daripada nerusin sesi lama.
                -- v4.56: PANEL SELALU DIDULUIN. Patokannya: apa pun yang berubah
                -- di panel (perintah baru, assign PS baru) -> berhenti, kerjain
                -- yang baru. Dulu cuma daftar perintah tertentu yang bisa nyerobot,
                -- jadi instruksi lain nunggu sesi lama kelar (bisa bermenit-menit).
                -- v4.57: JANGAN pakai potret lokal. Dulu psAwal dipotret pas mulai
                -- dan gak pernah diperbarui -> perubahan yang SAMA bikin batal
                -- berulang-ulang, worker gak pernah kelar buka client (kerasa lemot
                -- banget). Sekarang pembandingnya psGantiKerjakan -- yang di-update
                -- pas perubahan itu BENERAN dikerjain.
                local cmdAwal   = (isi or ""):upper()
                -- v4.57: REM. Sekali batal karena PS berubah, kasih jeda sebelum
                -- boleh batal lagi karena alasan yang sama -- biar gak muter
                -- "batal -> mulai -> batal" dalam hitungan detik.
                local batalTerakhir = 0
                local function batal()
                    if ada_stop() then return true end   -- stop lokal juga ngebatalin
                    local r = api_get(cfg, "/perintah?tim=" .. cfg.tim)

                    -- assign PS berubah (panel / suplai otomatis mindahin akun)
                    local psSkrg = tonumber((r or ""):match('"psGanti"%s*:%s*(%d+)')) or 0
                    if psGantiKerjakan > 0 and psSkrg > psGantiKerjakan
                       and (os.time() - batalTerakhir) >= 30 then
                        batalTerakhir = os.time()
                        warn("assign PS berubah dari panel -> berhenti, ngerjain yang baru")
                        return true
                    end

                    -- perintah dari panel. FORCE SENGAJA dikecualiin: panel suka
                    -- ngirim FORCE otomatis abis REJOIN/FRONT/GRID -- kalau itu
                    -- dianggap "perintah baru", worker malah motong kerjaannya
                    -- sendiri. Selain FORCE = instruksi beneran -> didahulukan.
                    local iAsli = ambil_str(r, "isi") or ""
                    local i = iAsli:upper()
                    if i ~= "" and i ~= cmdAwal and not i:find("^FORCE$") then
                        -- v6.29: kalau LOGIN, SIMPEN isi aslinya (huruf kecil) biar
                        -- gak keburu ketimpa FORCE sebelum diproses. Loop utama
                        -- jalanin dari simpanan ini, bukan baca ulang backend.
                        if iAsli:match("^LOGIN:") then
                            KICK_DIURUS["login_tertunda"] = iAsli
                            warn("  >> LOGIN disimpen buat diproses: " .. iAsli)
                        end
                        warn("perintah baru dari panel: " .. i .. " -> berhenti, itu duluan")
                        return true
                    end
                    -- jaring lama: perintah yang WAJIB nyerobot walau sama isinya
                    return i:find("STANDBY") ~= nil
                        or i:find("STOP") ~= nil
                        or i:find("KILL") ~= nil
                        or i:find("REJOIN") ~= nil
                        or i:find("CLOSE") ~= nil
                        or i:find("PAKSA") ~= nil   -- v9.63: Start Paksa langsung nyela loop
                end
                -- v4.33: tabel ikut ke-update PAS lagi buka client. Dulu redraw
                -- cuma di loop utama, sedangkan open_all ngeblok bermenit-menit ->
                -- tabel nampilin data LAMA (client udah nyala tapi ketulis "off").
                local function lapor_sela()
                    refresh_status(); lastStatusCek = os.time()
                    gambar_tabel(isi)
                    lapor(cfg, isi, cacheRun)
                end

                local h = open_all(cfg, only, batal, lapor_sela, mapLink, mapAkun)

                -- v6.60: abis buka client (open_all makan menit-menitan), RESET
                -- jadwal cek captcha -> iterasi berikutnya LANGSUNG cek (client
                -- udah kebuka & mungkin kena captcha). Tanpa ini, cek captcha
                -- jalan di AWAL iterasi (sebelum client dibuka -> 0 kandidat),
                -- terus nunggu 1 iterasi penuh (~5 menit) baru cek lagi.
                lastCekCaptcha = 0

                -- v6.31: FORCE di-break sama LOGIN -> PROSES LOGIN LANGSUNG di sini,
                -- gak nunggu iterasi baru (yang keburu ketimpa FORCE). batal()
                -- nyimpen login_tertunda; kita eksekusi sekarang juga.
                if KICK_DIURUS["login_tertunda"] then
                    local isiL = KICK_DIURUS["login_tertunda"]
                    KICK_DIURUS["login_tertunda"] = nil
                    local akunL, clientL = isiL:match("^LOGIN:([^:]+):([^:]+)")
                    if akunL and clientL then
                        print("")
                        print(C.BOLD .. C.C .. ">>> JALANIN PERINTAH LOGIN (langsung) <<<" .. C.N)
                        info(("Suntik cookie: %s -> client %s"):format(akunL, clientL))
                        KICK_DIURUS["mati:" .. akunL] = nil
                        local pkgL = clientL:find("%.") and clientL or ("com.roblox." .. clientL)
                        os.execute(("timeout 120 %s login %s %s"):format(
                            (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium",
                            akunL, pkgL:gsub("com%.roblox%.", "")))
                        ok(("LOGIN selesai: %s -> %s"):format(akunL, clientL))
                        -- v6.33: JANGAN balikin FORCE (nimpa LOGIN berikutnya).
                        lastIsi = isiL
                        refresh_status(); lastStatusCek = os.time()
                    end
                end

                if h.ok > 0 or h.gagal > 0 then
                    local ringkas = string.format("%d jalan, %d gagal, %d dilewat",
                        h.ok, h.gagal, h.lewat)
                    if h.gagal > 0 then
                        err("Kelar: " .. ringkas)
                        err("Gagal: " .. table.concat(h.nama_gagal, ", "))
                        notify("Velium "..cfg.tim, "GAGAL "..h.gagal.." client â€” cek Termux")
                    else
                        ok("Kelar: " .. ringkas)
                        notify("Velium "..cfg.tim, isi.." -> "..h.ok.." client jalan")
                    end
                else
                    info("'"..isi.."' -> semua client udah jalan")
                end
                -- v9.283: REFRESH grace SEMUA client ke waktu SELESAI buka. Bug user:
                -- grace di-set dari AWAL FORCE (v9.277), tapi buka semua butuh ~3 menit
                -- (1-1). Pas client terakhir kebuka, grace dari awal (240s) udah mau abis
                -- -> client yg denyutnya masih loading/stale langsung ke-flag MATI +
                -- rejoin. User minta: nunggu ~3 menit dari client TERAKHIR kebuka. Set
                -- tembak_ts = SEKARANG (waktu selesai) buat semua -> denyut-cek diem
                -- 240s dari sini, kasih semua client waktu boot + nulis denyut.
                do
                    local tSelesai = os.time()
                    for _, pk in ipairs(split(cfg.pkgs or "")) do
                        KICK_DIURUS["tembak_ts:" .. pk] = tSelesai
                    end
                    info("Grace SEMUA client di-refresh -> denyut-cek nunggu ~3 menit dari sekarang (client terakhir kebuka)")
                end
                lastOpen = os.time()
                lastStatus = 0   -- paksa lapor abis buka
            else
                -- v4.10: status ditampilin lewat tabel, gak print baris ini lagi
            end
        else
            -- v4.10: status standby ditampilin lewat tabel
        end

        if (now - lastStatus) >= cfg.status_sec then
            local jalan, total = lapor(cfg, isi, cacheRun)
            notify("Velium "..cfg.tim, jalan.."/"..total.." client jalan"..(hit and " Â· FORCE" or ""))
            lastStatus = now
        end


        -- ============================================================
        -- v5.29: SCRIPT PER TIM DARI PANEL.
        -- Panel nentuin tim ini jalanin script apa; URL-nya nebeng di /perintah
        -- (yang emang udah di-poll), jadi gak nambah request.
        -- Ganti script = tulis ulang autoexec + REJOIN. Rejoin-nya WAJIB:
        -- Delta cuma baca folder Autoexecute pas aplikasi masuk game, jadi
        -- client yang lagi jalan bakal tetep pakai script lama sampai join ulang.
        -- ============================================================
        do
            local scrUrl   = ambil_str(resp, "scriptUrl") or ""
            local scrNama  = ambil_str(resp, "scriptNama") or ""
            local scrGanti = tonumber((resp or ""):match('"scriptGanti"%s*:%s*(%d+)')) or 0
            if scrUrl ~= "" and scrGanti > 0 and scrGanti ~= SCRIPT_KERJAKAN then
                if scrUrl ~= SCRIPT_URL_AKHIR then
                    tambahLog("PANEL: script diganti -> " .. (scrNama ~= "" and scrNama or scrUrl))
                    if tulis_autoexec(cfg, scrUrl) then
                        SCRIPT_URL_AKHIR = scrUrl
                        -- Client yang lagi jalan masih megang script LAMA -- Delta
                        -- cuma baca Autoexecute pas masuk game. Jadi ditutup;
                        -- yang buka lagi biar blok FORCE di bawah (kalau STANDBY,
                        -- ya emang sengaja gak dibuka).
                        tambahLog("Tutup semua client -- script baru kepakai pas join ulang")
                        close_all(cfg, nil, mapLink)
                    else
                        tambahLog("! gagal nulis autoexec buat script baru")
                    end
                end
                SCRIPT_KERJAKAN = scrGanti
            end
        end

        -- v4.9: AUTO-REJOIN per client. cek tiap akun (dari mapping client<->akun)
        -- apakah masih lapor ke panel. akun yg keluar game -> script off -> berhenti
        -- lapor. kalau > auto_rejoin_menit -> rejoin client itu doang (bukan semua).
        -- cuma jalan kalau auto_rejoin nyala (FORCE aktif, gak STANDBY).
        -- v4.51: kalau panel BARU AJA mindahin/mulangin akun, jangan nunggu
        -- giliran 60 detik -- langsung masuk blok ini dan kerjain.
        local psGantiPeek = tonumber((resp or ""):match('"psGanti"%s*:%s*(%d+)')) or 0
        local adaTitahBaru = (psGantiPeek > 0 and psGantiPeek ~= psGantiKerjakan)
        if false then  -- v7.49: auto-rejoin DIMATIIN (ganti loop grafis)
            lastAutoRejoin = now
            -- v9.243: refresh mapping 10 menit -> 90 DETIK. Dan kalau ada akun baru/ganti
            -- (username berubah) -> auto_assign LANGSUNG (gak nunggu siklus). Akun baru
            -- dibuat di client -> kedeteksi + keassign ke device cepet -> template bener.
            if (now - lastMapRefresh) >= 90 then
                local adaBaru = refresh_map()
                lastMapRefresh = now
                if adaBaru then
                    warn("[map] akun baru/ganti kedeteksi -> auto-assign LANGSUNG")
                    auto_assign_tim(); lastAssign = now
                end
            end
            if (now - lastAssign) >= 180 or _PAKSA_ASSIGN then _PAKSA_ASSIGN = false; auto_assign_tim(); lastAssign = now end   -- v9.242: 600s -> 180s (akun baru ke-assign lebih cepet -> template bener). v9.256: _PAKSA_ASSIGN dari pasang (place berubah) -> assign SEKETIKA (pindah tab GAG 1)
            -- v4.51: keputusan panel LANGSUNG dikerjain. psGanti dibaca dari
            -- /perintah yang emang udah di-poll tiap beberapa detik -- jadi begitu
            -- panel mindahin/mulangin akun, worker nyusul dalam hitungan detik,
            -- gak nunggu giliran 60 detik.
            local psBaruDariPanel = adaTitahBaru
            if psBaruDariPanel then
                psGantiKerjakan = psGantiPeek
                tambahLog("PANEL: ada perubahan server -> langsung dikerjain")
            end
            if (psBaruDariPanel or (now - lastPsRefresh) >= 60) and MODE_JALAN then
                -- v8.96: TAMBAH guard MODE_JALAN. Bug user (curiga grid nyangkut pas
                -- standby): loop PS-pindah rejoin client walau STANDBY -> open_one ->
                -- grid_satu pakai PKGS_AKTIF yg BASI (pas standby hitTop=false, PKGS_
                -- AKTIF gak ke-update) -> grid salah/nyangkut. Pas standby JANGAN
                -- rejoin sama sekali (client emang gak jalan). Refresh PS aja boleh,
                -- rejoin-nya nanti pas FORCE.
                -- v4.23: PS pindah? -> rejoin client itu doang, biar masuk PS baru.
                local psLama = {}
                for k, v in pairs(mapPsNama) do psLama[k] = v end
                refresh_ps(); pcall(refresh_ps_getps)
                lastPsRefresh = now
                -- v4.61: KUMPULIN dulu semua yang pindah, TUTUP BARENGAN, baru
                -- buka satu-satu. Dulu tiap client ditutup+dibuka sendiri-sendiri
                -- -> 3 client bisa makan semenit lebih cuma buat nutup.
                local pindahPkg = {}
                -- v9.48: filter PKGS_AKTIF (jalan 6 -> cuma cek pindah PS 6, bukan 10)
                local aktifPS = nil
                if PKGS_AKTIF and #PKGS_AKTIF > 0 then
                    aktifPS = {}
                    for _, p in ipairs(PKGS_AKTIF) do aktifPS[p] = true end
                end
                for _, pkg in ipairs(split(cfg.pkgs)) do
                    local baru = mapPsNama[pkg] or ""
                    local lama = psLama[pkg]
                    -- lama == nil = baru pertama kali kebaca (jangan rejoin, itu bukan pindah)
                    -- v9.122: rotasi_on -> tim 2 dilewat (standby, jangan pindah-server-rejoin)
                    if (not aktifPS or aktifPS[pkg]) and lama ~= nil and baru ~= lama and not rotasi_lewat(cfg, pkg) then
                        tambahLog(string.format("PINDAH SERVER: %s  %s -> %s",
                            (mapAkun[pkg] or pkg:gsub("com%.roblox%.","")),
                            (lama ~= "" and lama or "public"),
                            (baru ~= "" and baru or "public")))
                        pindahPkg[#pindahPkg+1] = pkg
                    end
                end
                if #pindahPkg > 0 then
                    close_all(cfg, pindahPkg, mapLink)   -- SEKALI JALAN buat semuanya
                    os.execute("sleep 2")
                    for i, pkg in ipairs(pindahPkg) do
                        open_one(cfg, pkg, mapLink[pkg], "pindah-warehouse")
                        tambahLog("   -> " .. (mapAkun[pkg] or pkg:gsub("com%.roblox%.",""))
                                  .. " dibuka lagi di " .. ((mapPsNama[pkg] or "") ~= "" and mapPsNama[pkg] or "public"))
                        -- jeda cuma ANTAR buka (biar RAM gak kaget), bukan tiap tutup
                        if i < #pindahPkg then os.execute("sleep " .. (cfg.stagger_sec or 15)) end
                    end
                end
            end
            -- ambil semua status akun dari panel sekali
            local stat = api_get(cfg, "/stat")
            local ambang = (tonumber(cfg.auto_rejoin_menit) or 8) * 60
            -- v4.38: ambang CEPAT khusus buat ngintip dialog error (disconnect).
            -- Nungguin 8 menit kelamaan kalau cuma kena "Error Code 277".
            local ambangDc = (tonumber(cfg.disconnect_menit) or 3) * 60
            -- v4.86: cek lisensi SEKALI per ronde (berkasnya dipakai bareng semua
            -- client, jadi gak usah dicek per client). Kalau hilang/basi, client
            -- yang diem JANGAN dibunuh -- yang kurang itu kunci, bukan restart.
            local licKead, licUmur = lisensi_keadaan(cfg)
            -- v5.01: cuma "hilang" yang bikin worker berhenti nyentuh client.
            -- "basi" (lewat umur) TIDAK -- karena Delta cuma meriksa kunci pas
            -- aplikasi MULAI. Client yang udah jalan tetep aman walau lisensinya
            -- udah 28 jam, selama dia gak keluar. Kalau umur doang dipakai buat
            -- berhenti ngurus, client yang cuma putus koneksi biasa jadi gak
            -- pernah di-rejoin -- farm macet gara-gara umur berkas.
            local butuhKey = (licKead == "hilang")
            local licTua   = (licKead == "basi")
            if butuhKey and (os.time() - (LAPOR_KEY_AT or 0)) > 600 then
                LAPOR_KEY_AT = os.time()
                if cfg.auto_key == true then
                    tambahLog("BUTUH KEY: lisensi Delta HILANG -- worker bakal nyari sendiri")
                else
                    tambahLog("BUTUH KEY: lisensi Delta HILANG -- tap tombolnya manual (2x), terus: velium key")
                end
            end
            -- v8.16: SEMUA deteksi rejoin per-client (kick/script-off/home/
            -- disconnect/diem/logcat) DIMATIIN (user minta). Intinya semua kasus
            -- 'client keluar = grafis rendah' -> udah ketangkep LOOP GRAFIS 2 MENIT.
            if false then
            for _, pkg in ipairs(split(cfg.pkgs)) do
                local akun = mapAkun[pkg]
                -- v6.57: KALAU KENA CAPTCHA -> SKIP dari auto-rejoin. Jangan
                -- di-rejoin (percuma, captcha butuh solve manual). Cek dulu masih
                -- captcha apa nggak; kalau udah solved (masuk game), clear & lanjut.
                -- v6.67: kalau UDAH ketandai captcha -> langsung skip (gak usah
                -- cek dump lagi). Cek dump CUMA buat yang belum ketandai. Penanda
                -- dilepas pas client RUN (masuk game) di tempat lapor -- BUKAN
                -- dari cek "bukan captcha" (captcha bolak-balik, salah clear ->
                -- di-rejoin lagi).
                -- v6.68: guard captcha PAKAI bridge_fresh (bukan cacheRun --
                -- cacheRun bisa true padahal nyangkut captcha -> guard gak jalan
                -- -> tetep tembak link PS). bridge_fresh = client lapor beneran
                -- apa nggak. Gak lapor + hidup = kandidat captcha -> cek dump.
                -- v7.41: DUMP CAPTCHA di guard DIHAPUS (uiautomator lambat). Cuma
                -- cek PENANDA captcha (dari jalur diem 5menit). Kalau udah ketandai
                -- captcha -> skip. Kalau belum -> lanjut jalur diem di bawah.
                local lewatiCaptcha = false
                if KICK_DIURUS["captcha:" .. pkg] then
                    lewatiCaptcha = true   -- udah kena captcha -> skip auto-rejoin
                end
                if akun and not lewatiCaptcha then
                    -- cari "ts" akun ini di /stat. format: ..."nama":"fifinx_5"...,"ts":123...
                    local blok = stat:match('{[^{}]-"nama"%s*:%s*"' .. akun .. '"[^{}]-}')
                    local ts = blok and tonumber(blok:match('"ts"%s*:%s*(%d+)')) or nil
                    local skrgSrv = ambil_num(stat, "skrg") or now   -- v4.53: dulu selalu nil -> pakai jam LOKAL

                    -- ============================================================
                    -- v5.71: LAPORAN KICK dari script (star_seed v3.12).
                    --
                    -- Ini nutup lubang yang lama: worker GAK BISA baca dialog
                    -- kick sendiri (uiautomator 0 teks di RF -- v4.85). Jadi
                    -- dulu cuma tau "berhenti lapor", terus nunggu
                    -- auto_rejoin_menit (3 menit) tanpa tau sebabnya.
                    -- Sekarang script yang lapor DARI DALAM, di mana dialognya
                    -- kebaca -- lengkap sama sebabnya.
                    --
                    -- Bedanya penting, dan ini yang gak bisa ditebak dari luar:
                    --   gagal-muat-data / koneksi -> ngulang ITU OBATNYA
                    --   anti-cheat                -> ngulang MAKIN PARAH
                    -- Yang kedua SENGAJA gak direjoin; cuma dicatet biar
                    -- keliatan di log. Rejoin terus ke akun kena anti-cheat itu
                    -- mancing hukuman lebih berat.
                    -- ============================================================
                    local kickKode = blok and tonumber(blok:match('"kick"%s*:%s*(%d+)')) or nil
                    local kickTs   = blok and tonumber(blok:match('"kick_ts"%s*:%s*(%d+)')) or nil
                    local kickSbb  = blok and blok:match('"kick_sebab"%s*:%s*"([^"]*)"') or ""
                    -- cuma yang BARU (<5 menit) -- laporan lama gak boleh bikin
                    -- rejoin berulang tiap ronde
                    if kickKode and kickKode > 0 and kickTs
                       and (skrgSrv - kickTs) < 300
                       and not KICK_DIURUS[akun .. ":" .. kickTs] then
                        KICK_DIURUS[akun .. ":" .. kickTs] = true
                        -- ============================================================
                        -- v5.72: DIJATAH, dan ini BUKAN kehati-hatian berlebihan.
                        --
                        -- Catatan gag2 v6.5 (ditulis atas permintaan sendiri):
                        --   "auto-rejoin (teleport balik pas 267) malah sering
                        --    bikin error 267 LAGI -- teleport-nya sendiri
                        --    ketrigger anti-cheat / data load gagal."
                        -- Jadi rejoin otomatis pas 267 UDAH PERNAH DICOBA dan
                        -- DIBUANG. Rejoin di sini beda jalur (force-stop + buka
                        -- ulang aplikasi, bukan teleport dalam game), tapi
                        -- risiko badainya sama: 267 -> rejoin -> 267 -> rejoin.
                        --
                        -- Makanya disambungin ke JATAH BUNUH yang udah ada
                        -- (maks 3x / 30 menit per client, v4.83) -- bukan bikin
                        -- penjatah kedua yang bisa beda perilaku.
                        -- Lewat jatah -> berhenti, catet aja. Client yang 267
                        -- terus itu masalahnya BUKAN di rejoin: bisa akun kena
                        -- limit, atau server datastore-nya yang lagi rusak.
                        -- ============================================================
                        if kickSbb == "anti-cheat" then
                            tambahLog(("KICK %d %s: %s -- TIDAK direjoin (ngulang malah makin parah)")
                                      :format(kickKode, kickSbb, akun))
                            RIW.catat("KICK", akun,
                                ("kode=%d sebab=%s TIDAK-direjoin"):format(kickKode, kickSbb))
                        elseif sisa_jatah_kill(pkg) <= 0 then
                            tambahLog(("KICK %d %s: %s -- JATAH HABIS (3x/30menit), berhenti rejoin")
                                      :format(kickKode, kickSbb ~= "" and kickSbb or "?", akun))
                            tambahLog("  267 berulang = bukan masalah rejoin. Cek akun/limit manual.")
                            RIW.catat("KICK", akun,
                                ("kode=%d sebab=%s jatah-habis"):format(kickKode, kickSbb))
                        else
                            catat_kill(pkg)
                            tambahLog(("KICK %d %s: %s -> rejoin (sisa jatah %d)")
                                      :format(kickKode, kickSbb ~= "" and kickSbb or "?",
                                              akun, sisa_jatah_kill(pkg)))
                            setAksi("rejoin " .. akun .. " (kick " .. kickKode .. ")")
                            -- v5.73: DUA baris, bukan satu gabungan.
                            -- Nama jenis SENGAJA gak digabung ("REJOIN-KICK")
                            -- -- nama begitu ngandung "KICK" DAN "REJOIN", jadi
                            -- pas dianalisis satu kejadian kehitung dua kali dan
                            -- kesimpulannya ngaco. Ketangkep pas uji: pola badai
                            -- yang jelas malah dibilang "belum cukup data".
                            RIW.catat("KICK", akun,
                                ("kode=%d sebab=%s"):format(kickKode, kickSbb))
                            RIW.catat("REJOIN", akun,
                                ("karena=kick sisaJatah=%d"):format(sisa_jatah_kill(pkg)))
                            -- jeda sebelum buka ulang. Roblox nolak muat data
                            -- kalau join-nya kerapetan -- itu justru sumber 267
                            -- yang kita coba obatin.
                            os.execute("sleep 8")
                            -- v7.84: force-stop DIHAPUS (user minta). Langsung
                            -- open_one (cara Pandora re-join tanpa kill).
                            open_one(cfg, pkg, mapLink[pkg], "diem-diagnosa")
                            os.execute("sleep 3")
                            refresh_status(); lastStatusCek = os.time()
                        end
                    end

                    -- v5.04: BERAPA LAMA DIEM. Dulu semua tindakan digantung ke 'ts'
                    -- (kapan terakhir lapor). Masalahnya client yang nyangkut di Home
                    -- BELUM PERNAH lapor sama sekali -> ts kosong -> SELURUH blok ini
                    -- dilewat -> worker diem selamanya. Itu persis keluhan "kalau udah
                    -- nyangkut, gak ngapa-ngapain lagi".
                    -- Sekarang: kalau belum pernah lapor, umur diemnya dihitung dari
                    -- kapan worker PERTAMA liat dia idup tapi bisu.
                    local diem
                    if ts then
                        diem = skrgSrv - ts
                        PERTAMA_DIEM[pkg] = nil
                    elseif cacheRun[pkg] then
                        PERTAMA_DIEM[pkg] = PERTAMA_DIEM[pkg] or now
                        diem = now - PERTAMA_DIEM[pkg]
                    end
                    -- v6.49: simpen "off berapa lama" per client biar dikirim ke
                    -- panel (nampilin "script off X menit").
                    if diem then KICK_DIURUS["offlama:" .. pkg] = diem
                    else KICK_DIURUS["offlama:" .. pkg] = nil end

                    -- v7.60: SCRIPT OFF >= 3 MENIT -> masukin lagi (aktif lagi).
                    -- Dulu 5 menit + dump uiautomator. Sekarang: cek CAPTCHA via
                    -- WEBVIEW FD (ringan, gak uiautomator). Kalau captcha -> skip
                    -- (solve manual). Kalau BUKAN captcha (script mati/nyangkut) ->
                    -- FORCE-STOP + masukin lagi (aman sekarang -- isolasi Pandora,
                    -- gak bikin client lain keluar). Cuma sekali per sesi off.
                    -- v7.65: SCRIPT OFF >= 3 MENIT -> masukin lagi. FIX: dulu pakai
                    -- flag diag: yang cuma DISET SEKALI -> client off lama cuma dicoba
                    -- 1x, gagal, terus DIEM SELAMANYA (keluhan: off 1 jam gak dimasukin).
                    -- Sekarang: simpen KAPAN terakhir dicoba (diag: = timestamp).
                    -- Boleh coba LAGI kalau udah lewat 180s dari coba terakhir. Jadi
                    -- client yang gagal masuk dicoba ulang tiap 3 menit sampai masuk.
                    local terakhirCoba = KICK_DIURUS["diag:" .. pkg]
                    local bolehCoba = (not terakhirCoba) or (now - terakhirCoba) >= 180
                    if diem and diem >= 180 and pkg_running(pkg) and bolehCoba then
                        KICK_DIURUS["diag:" .. pkg] = now   -- catat kapan dicoba
                        local akD = mapAkun and mapAkun[pkg] or pkg:gsub("com%.roblox%.","")
                        -- v8.15: CEK GRAFIS DULU sebelum rejoin. Client bisa SEHAT di
                        -- dalam game (grafis tinggi) tapi script-nya yg off (belum
                        -- inject / map baru / dll). JANGAN rejoin client sehat! Cuma
                        -- rejoin kalau grafis RENDAH (bener-bener keluar/Home).
                        local gNow = grafis_kb(pkg) or 0
                        if gNow >= GAME_AMBANG_KB then
                            -- SEHAT di game, cuma script off -> JANGAN rejoin.
                            info(("SCRIPT OFF %s (off %dm) TAPI grafis %.0f MB = DI GAME -> gak di-rejoin (client sehat)"):format(
                                akD, math.floor(diem/60), gNow/1024))
                            KICK_DIURUS["offlama:" .. pkg] = nil   -- reset (biar gak spam)
                        else
                        local isCap, nWeb = cek_captcha_webview(pkg)
                        if isCap then
                            warn(("SCRIPT OFF %s (off %dm) -> CAPTCHA (webview %d fd). Solve manual."):format(akD, math.floor(diem/60), nWeb))
                            KICK_DIURUS["captcha:" .. pkg] = akD
                        else
                            -- bukan captcha + grafis rendah -> bener keluar -> MASUKIN LAGI
                            info(("SCRIPT OFF %s (off %dm, grafis %.0f MB) -> masukin lagi"):format(akD, math.floor(diem/60), gNow/1024))
                            RIW.catat("REJOIN", akD, "karena=script-off-3menit")
                            -- v7.84: force-stop DIHAPUS (user minta). Langsung tembak.
                            open_one(cfg, pkg, mapLink and mapLink[pkg] or nil, "script-off-3menit")
                            TERAKHIR_BUKA[pkg] = os.time()
                            jaga_depan(cfg, mapLink)
                            local msk, mbk = cek_masuk_game(pkg, 30, cek_batal)
                            if msk then info(("  -> %s MASUK lagi (grafis %.0f MB)"):format(akD, mbk or 0))
                            else info(("  -> %s belum masuk (grafis %.0f MB) -> coba ronde berikutnya"):format(akD, mbk or 0)) end
                            refresh_status(); lastStatusCek = os.time()
                            gambar_tabel(isi)
                        end
                        end   -- v8.15: tutup if grafis (di game -> gak rejoin)
                    end
                    -- reset penanda diag kalau script udah jalan lagi (diem = nil)
                    if not diem and KICK_DIURUS["diag:" .. pkg] then
                        KICK_DIURUS["diag:" .. pkg] = nil
                    end

                    if diem and butuhKey then
                        -- v4.86: lisensi hilang/basi -> script emang GAK BAKAL jalan
                        -- sampai kunci masuk. Dibunuh/dibuka ulang cuma muter-muter
                        -- sambil ngabisin RAM. Diemin aja, nunggu `velium key`.
                        nudgeCnt[pkg] = nil
                    -- v5.05: client yang BELUM PERNAH lapor itu PASTI nyangkut
                    -- (Home / layar key) -- gak mungkin sehat. Jadi ambangnya
                    -- pendek: 60 detik. Client yang PERNAH lapor tetep pakai
                    -- ambang lama, soalnya normalnya dia emang cuma lapor tiap
                    -- ~120 detik -- kalau ikut 60 detik, client SEHAT bakal
                    -- ditembakin terus percuma.
                    elseif diem and diem > (ts and math.min(ambangDc, ambang)
                                                or (tonumber(cfg.home_detik) or 60)) then
                        -- v4.21: bridge diem > ambang. TAPI cek dulu client masih di
                        -- game apa nggak (pkg_running). Android suka BEKUIN Roblox bg
                        -- (proses idup, script beku, gak lapor) -> keliatan "off"
                        -- padahal masih di server. jangan asal kill.
                        if pkg_running(pkg) then
                            -- v4.38: sebelum nebak-nebak, INTIP layarnya dulu. Kalau
                            -- ada dialog error Roblox (Disconnected / Error 277), itu
                            -- BUKAN beku -- dibangunin gak bakal nolong. Harus dibunuh
                            -- terus dibuka ulang biar join dari awal.
                            local errUi, errSifat = cek_error_ui(cfg, pkg, mapLink)
                            if errUi and errSifat == "captcha" then
                                -- v6.51: KENA CAPTCHA (verif bot). Rejoin percuma --
                                -- captcha butuh solve manual. Lapor ke panel (badge)
                                -- + SKIP client ini dari loop (jangan dipaksa join
                                -- terus -> makin dicurigai). Nunggu user solve manual.
                                local akCap = mapAkun and mapAkun[pkg] or akun
                                warn(string.format("CAPTCHA: %s (%s) kena verif bot -> skip, solve manual", akun, pkg:gsub("com%.roblox%.","")))
                                KICK_DIURUS["captcha:" .. pkg] = akCap or akun
                                nudgeCnt[pkg] = nil
                                errUi = nil
                            elseif errUi and errSifat == "manual" then
                                -- percuma diulang (layar KEY, link PS salah, di-kick
                                -- script, place dibatesin). Diulang cuma muter-muter ->
                                -- catet aja, biar keliatan di panel & dibenerin manual.
                                tambahLog(string.format("PERLU DICEK: %s kena '%s' -- masuk ulang gak bakal nolong", akun, errUi))
                                nudgeCnt[pkg] = nil
                                errUi = nil   -- jangan diapa-apain lagi ronde ini
                            elseif errUi and errSifat == "tunggu" then
                                -- lagi dibatesin (kebanyakan nyoba / server ngadat).
                                -- Buru-buru masuk ulang malah makin diblok -> tutup
                                -- aja, biarin adem; ronde berikutnya baru dibuka.
                                tambahLog(string.format("DIBATESIN: %s kena '%s' -> ditutup dulu, adem ~1 menit", akun, errUi))
                                close_all(cfg, pkg, mapLink)
                                nudgeCnt[pkg] = nil
                                errUi = nil
                            elseif errUi and errSifat == "home" then
                                -- v5.04: nyangkut di Home -> LANGSUNG TEMBAK LINK PS,
                                -- JANGAN dibunuh dulu. Di layar Home, Roblox BELUM di
                                -- dalam game, jadi 'am start -d <link>' beneran jalan --
                                -- ini kebukti gak sengaja waktu kalibrasi tap: client
                                -- yang lagi di layar key kena link, terus beneran join.
                                -- (Beda sama client yang UDAH di dalam game: di situ
                                -- link jadi no-op, makanya dulu mesti ditutup dulu.)
                                -- Dicoba sampai 4x -- murah, gak destruktif, gak
                                -- ngilangin progress. Bunuh cuma pilihan terakhir.
                                -- v5.05: nyangkut di Home -> REJOIN TERUS, GAK PERNAH DIBUNUH.
                                -- Nembak link itu murah & gak ngilangin apa-apa; kalau
                                -- 10x pun belum masuk, dibunuh juga gak bakal nolong
                                -- (kasus layar key ditangani jalur bypass sendiri).
                                -- v8.15: cek grafis dulu -- kalau grafis tinggi (di
                                -- game), JANGAN tembak walau uiautomator bilang home
                                -- (deteksi UI bisa salah baca). Client sehat jangan
                                -- diganggu.
                                local gHome = grafis_kb(pkg) or 0
                                if gHome >= GAME_AMBANG_KB then
                                    tambahLog(string.format("HOME? %s tapi grafis %.0f MB = DI GAME -> gak ditembak (sehat)",
                                        akun, gHome/1024))
                                    nudgeCnt[pkg] = nil
                                    errUi = nil
                                else
                                nudgeCnt[pkg] = (nudgeCnt[pkg] or 0) + 1
                                tambahLog(string.format("HOME: %s %s -> rejoin ke PS (percobaan %d), GAK dibunuh",
                                    akun, errUi, nudgeCnt[pkg]))
                                open_one(cfg, pkg, mapLink[pkg], "home-nudge")
                                os.execute("sleep 5")   -- kasih waktu join
                                errUi = nil             -- jangan jatuh ke blok bunuh
                                end
                            end
                            if errUi then
                                -- v4.83: kill DIJATAH. Kalau client ini udah dibunuh
                                -- berkali-kali dalam waktu dekat, berarti restart bukan
                                -- obatnya -- berhenti, catet, biar diurus manual.
                                if sisa_jatah_kill(pkg) <= 0 then
                                    tambahLog(string.format("PERLU DICEK: %s kena '%s' -- udah dibunuh %dx/30menit, DISTOP dulu",
                                        akun, errUi, KILL_MAKS))
                                    nudgeCnt[pkg] = nil
                                else
                                -- v6.70: DISCONNECT/koneksi terputus -> MASUK KEMBALI
                                -- (open_one), GAK di-kill (close_all). User minta:
                                -- semua disconnect cukup masuk lagi, jangan bunuh.
                                -- am start munculin window + join link -> masuk lagi.
                                tambahLog(string.format("DISCONNECT: %s kena '%s' -> masuk kembali (gak dibunuh)", akun, errUi))
                                open_one(cfg, pkg, mapLink[pkg], "disconnect-errui")
                                notify("Velium "..cfg.tim, akun .. " " .. errUi .. " -> masuk kembali")
                                nudgeCnt[pkg] = nil
                                os.execute("sleep " .. (cfg.stagger_sec or 10))
                                end
                            elseif diem > ambang then
                            -- gak ada dialog error, dan udah lewat ambang penuh
                            nudgeCnt[pkg] = (nudgeCnt[pkg] or 0) + 1
                            if nudgeCnt[pkg] <= 4 then
                                -- v5.04: dari 2x jadi 4x. 'am start -d <link>' itu murah
                                -- dan gak destruktif: kalau client UDAH di dalam game,
                                -- link-nya diabaikan (cuma jendelanya naik ke depan);
                                -- kalau BELUM (nyangkut Home/key), link-nya beneran
                                -- jalan dan dia join. Dua-duanya gak ngilangin apa-apa,
                                -- jadi gak ada alasan buru-buru bunuh.
                                tambahLog(string.format("DIEM: %s %dm gak lapor -> tembak link PS (%d/4), gak dibunuh",
                                    akun, math.floor(diem/60), nudgeCnt[pkg]))
                                open_one(cfg, pkg, mapLink[pkg], "diem-nudge")
                                os.execute("sleep 5")
                            else
                                -- udah dibangunin 2x masih diem -> script beneran mati -> rejoin penuh
                                -- v4.85: ikut kena JATAH. Sejak layar gak bisa dibaca lagi,
                                -- jalur inilah yang paling sering kepakai -- kalau gak dijatah,
                                -- client bermasalah balik dibunuh tiap ronde kayak dulu.
                                if sisa_jatah_kill(pkg) <= 0 then
                                    tambahLog(string.format("PERLU DICEK: %s diem terus -- udah di-rejoin %dx/30menit, DISTOP dulu",
                                        akun, KILL_MAKS))
                                    nudgeCnt[pkg] = nil
                                else
                                catat_kill(pkg)
                                -- v5.01: lisensi tua + client gak mau idup lagi = curiga
                                -- nyangkut di layar key. Delta baru minta kunci pas
                                -- MULAI, jadi curiganya baru masuk akal DI SINI --
                                -- pas client-nya emang lagi dibuka ulang.
                                if licTua then
                                    tambahLog(("   (lisensi Delta umur %s -- kalau abis ini tetep diem, kemungkinan nyangkut di layar key: jalanin `velium cari %s`)")
                                        :format(umur_ringkas(licUmur), pkg:gsub("com%%.roblox%%.", "")))
                                end
                                -- v6.70: JANGAN kill (close_all) -- cukup open_one
                                -- (masuk ulang ke server). User minta: nyangkut home
                                -- gak usah dibunuh, cukup masukin lagi. am start
                                -- munculin window + join link; kalau nyangkut home,
                                -- link-nya jalan (join). Lebih ringan, gak reset client.
                                tambahLog(string.format("AUTO-REJOIN: %s dibangunin 2x masih diem -> masuk ulang (gak dibunuh)", akun))
                                open_one(cfg, pkg, mapLink[pkg], "auto-rejoin-dibangunin")
                                notify("Velium "..cfg.tim, "masuk ulang "..akun.." (nyangkut)")
                                nudgeCnt[pkg] = nil
                                os.execute("sleep " .. (cfg.stagger_sec or 10))
                                end
                            end
                            end   -- v4.38: tutup cabang "gak ada dialog error"
                        elseif diem > ambang then
                            -- v6.70: keluar game -> MASUK KEMBALI (open_one), GAK
                            -- di-kill. Semua disconnect/keluar game cukup masuk lagi.
                            tambahLog(string.format("AUTO-REJOIN: %s off %dm -> masuk kembali (gak dibunuh)",
                                akun, math.floor(diem/60)))
                            open_one(cfg, pkg, mapLink[pkg], "auto-rejoin-offlama")   -- buka lagi ke PS-nya
                            notify("Velium "..cfg.tim, "masuk kembali "..akun.." (keluar game)")
                            nudgeCnt[pkg] = nil
                            os.execute("sleep " .. (cfg.stagger_sec or 10))  -- jeda sebelum cek berikutnya
                        end
                    elseif ts then
                        nudgeCnt[pkg] = nil   -- v4.21: client lapor sehat -> reset counter nudge
                        PERTAMA_DIEM[pkg] = nil
                    end
                end
            end
        end

        -- v4.54: SUPLAI punya jadwal SENDIRI, lepas dari gerbang auto-rejoin.
        -- Dulu nebeng di situ -> keputusan "akun ini udah cukup, pulang" baru
        -- DIBIKIN tiap 60 detik, terus nunggu giliran lagi buat dikerjain.
        -- Sekarang dicek tiap suplai_sec (bawaan 20 detik).
        if cfg.suplai_master == true and hit
           and (now - lastSuplaiCek) >= (cfg.suplai_sec or 20) then
            lastSuplaiCek = now
            local rs = api_get(cfg, "/suplai-cek")
            local nb  = ambil_num(rs, "nBerangkat") or 0
            local np  = ambil_num(rs, "nPulang") or 0
            local npd = ambil_num(rs, "nPindah") or 0
            if nb > 0 then tambahLog("SUPLAI: " .. nb .. " akun market dikumpulin ke PS leveling") end
            if np > 0 then tambahLog("SUPLAI: " .. np .. " akun market dipulangin (stok cukup)") end
            if npd > 0 then tambahLog("SUPLAI: " .. npd .. " akun market pindah gudang (leveling abis)") end
        end

        -- v4.52: jaga jendela tetep nongol. Delta nguncup -> Roblox disconnect
        -- ~15 detik kemudian, jadi jedanya mesti di bawah itu.
        -- v7.15: PAKSA 3 detik (user minta) -- abaikan config lama yang mungkin
        -- masih 7/15. jaga_depan pakai monkey (aman, gak nge-tap).
        if hit and (now - lastJagaDepan) >= 3 then
            lastJagaDepan = now
            jaga_depan(cfg, mapLink, cacheRun)   -- v4.63: pakai cache, gak dumpsys ulang
        end

        -- ============================================================
        -- v7.49: LOOP GRAFIS -- SATU-SATUNYA deteksi "out" sekarang. Semua jalur
        -- lama (mati-bareng, diem, nyangkut-home, auto-rejoin, cek-captcha) UDAH
        -- DIMATIIN. Logika: cek tiap client URUT, satu-satu:
        --   grafis >= 30MB (di game) -> lanjut client berikutnya
        --   grafis < 30MB (out/home) -> force-stop + tembak, cek grafis 30s
        -- Muter terus tiap ronde. Skip client yang cookie mati/ban (mati:).
        -- Cuma jalan pas FORCE (hit) & client udah pernah dibuka (lastOpen > 0).
        -- v8.24: BUANG syarat lisensiAda. Dari log user: FORCE + client jalan tapi
        -- loop grafis GAK MUNCUL -- karena lisensiAda cuma di-set di jalur
        -- non-fast (if not fast and not only). Kalau masuk lewat jalur fast
        -- (FORCE dari standby / re-inject), lisensiAda tetep false -> loop grafis
        -- skip selamanya. Padahal client udah jalan = lisensi PASTI ada. Jadi
        -- cukup syarat: FORCE + client udah kebuka.

        if hit and lastOpen > 0 then
            -- v8.01: interval cek all 2 MENIT (dulu tiap ronde). Cek grafis SEMUA
            -- client SEKALI (1 su call). Hitung PROGRESS: berapa di game / total.
            -- Counter dinamis -- kalau ada yang out lagi, "masuk" turun (balik).
            -- v8.44: LOOP GRAFIS LAMA DINONAKTIFIN. Deteksi client udah pindah ke
            -- DENYUT (loop lain, tiap 180s). Dulu loop ini (grafis, 120s) jalan
            -- BERBARENGAN -> dobel deteksi + konflik (grafis bilang OUT, denyut
            -- bilang in-game) + tembak barengan (padahal user mau 1-1 30s). Matiin
            -- dgn kondisi false biar gak jalan tapi struktur utuh.
            if false and (os.time() - (lastCekGrafis or 0)) >= 120 then
                lastCekGrafis = os.time()
                local pkgList = split(cfg.pkgs or "")
                local petaGrafis = grafis_semua(pkgList)
                -- hitung total yang PERLU diurus (bukan cookie mati) + berapa di game
                local perlu, diGame = 0, 0
                -- v9.47: filter PKGS_AKTIF (jalan 6 -> cek 6, bukan 10). Bug user:
                -- jalan 6 tapi antrian "4/10 di game". pkgList semua tanpa filter.
                local aktifSet = nil
                if cfg.rotasi_on then
                    -- v9.120: ROTASI -> cuma hitung/urus tim 1 (10 pkg pertama).
                    aktifSet = {}
                    for i = 1, math.min(TIM1_AKHIR, #pkgList) do aktifSet[pkgList[i]] = true end
                elseif PKGS_AKTIF and #PKGS_AKTIF > 0 then
                    aktifSet = {}
                    for _, p in ipairs(PKGS_AKTIF) do aktifSet[p] = true end
                end
                for _, pkg in ipairs(pkgList) do
                    local ak = mapAkun and mapAkun[pkg]
                    local diAktif = (not aktifSet) or aktifSet[pkg]
                    if diAktif and not (ak and KICK_DIURUS["mati:" .. ak]) then
                        perlu = perlu + 1
                        if (petaGrafis[pkg] or 0) >= GAME_AMBANG_KB then diGame = diGame + 1 end
                    end
                end
                tambahLog(("[antrian] %d/%d di game (%d perlu diurus)"):format(diGame, perlu, perlu - diGame))
                info(("[antrian] %d/%d di game (%d perlu diurus)"):format(diGame, perlu, perlu - diGame))
                -- v8.02: kalau SEMUA udah masuk (10/10) -> sekalian cek CAPTCHA
                -- (webview) tiap client + set interval berikutnya 1 MENIT (cek keluar
                -- lebih cepet). Kalau belum penuh -> fokus buka, interval 2 menit.
                if diGame >= perlu and perlu > 0 then
                    tambahLog("[antrian] SEMUA masuk -- cek captcha + interval jadi 1 menit")
                    for _, pkg in ipairs(pkgList) do
                        if cek_batal and cek_batal() then break end
                        local ak = mapAkun and mapAkun[pkg]
                        if not (ak and KICK_DIURUS["mati:" .. ak]) then
                            local isCap, nW = cek_captcha_webview(pkg)
                            if isCap then
                                tambahLog(("[antrian] %s CAPTCHA (webview %d) -> badge"):format(ak or pkg, nW))
                                if ak then KICK_DIURUS["captcha:" .. pkg] = ak end
                            end
                        end
                    end
                    -- interval berikutnya lebih cepet pas penuh (cek keluar sering).
                    -- trik: mundurin lastCekGrafis 30s -> 90-30 = 60s lagi cek.
                    lastCekGrafis = os.time() - 40
                end
            -- v8.12: TEMBAK SEMUA BARENG (user minta -- panel lain juga gitu).
            -- Dulu: loop tembak satu-satu + cek_masuk_game 30s per client (LAMA,
            -- 4 client out = 2 menit). Sekarang: kumpulin SEMUA yang OUT dulu,
            -- tembak SEMUA bareng (open_one doang, TANPA nungguin masing-masing).
            -- Yang belum masuk ketangkep ronde 90s berikutnya. Grafis map baru
            -- kadang cuma 23MB -> jangan terlalu ngandelin ambang, tapi <30 = OUT.
            local perluTembak = {}
            for _, pkg in ipairs(pkgList) do
                if cek_batal and cek_batal() then break end
                -- v9.47: skip client yg gak aktif (PKGS_AKTIF). Bug: jalan 6, tembak 10.
                if aktifSet and not aktifSet[pkg] then
                    -- gak aktif -> skip
                else
                local akun = mapAkun and mapAkun[pkg]
                if akun and KICK_DIURUS["mati:" .. akun] then
                    -- skip cookie mati/ban
                else
                    local g = petaGrafis[pkg] or 0
                    if g >= GAME_AMBANG_KB then
                        -- udah di game -> aman
                    else
                        -- OUT -> cek captcha dulu (percuma tembak kalau captcha)
                        local nama = pkg:gsub("com%.roblox%.", "")
                        local isCaptcha, nWeb = cek_captcha_webview(pkg)
                        if isCaptcha then
                            tambahLog(("[grafis] %s CAPTCHA (webview %d fd) -> skip (solve manual)"):format(
                                akun or nama, nWeb))
                            if akun then KICK_DIURUS["captcha:" .. pkg] = akun end
                        else
                            perluTembak[#perluTembak+1] = pkg
                        end
                    end
                end
                end
            end
            -- tembak SEMUA yang OUT bareng (open_one doang, gak nunggu per client)
            if #perluTembak > 0 then
                tambahLog(("[grafis] %d client OUT -> tembak SEMUA bareng"):format(#perluTembak))
                for _, pkg in ipairs(perluTembak) do
                    if cek_batal and cek_batal() then break end
                    local akun = mapAkun and mapAkun[pkg]
                    local nama = pkg:gsub("com%.roblox%.", "")
                    tambahLog(("[grafis] %s OUT (%.0f MB) -> masukin"):format(
                        akun or nama, (petaGrafis[pkg] or 0)/1024))
                    grid_satu(cfg, pkg)
                    open_one(cfg, pkg, mapLink and mapLink[pkg] or nil, "grafis-out")
                    TERAKHIR_BUKA[pkg] = os.time()
                end
                jaga_depan(cfg, mapLink)   -- munculin jendela SEKALI setelah tembak semua
                refresh_status(); lastStatusCek = os.time()
                gambar_tabel(isi)
            end
            end   -- v8.01: tutup if interval cek all
        end

        -- v7.51: LOGCAT STREAMING DIMATIIN. Dia nyalain `logcat > file` yang
        -- nulis SEMUA log terus-menerus (spam, file membengkak). Gak guna lagi --
        -- loop grafis (v7.49) udah gantiin deteksi out. Matiin biar gak spam.
        if false then
            lastRekamDc = now
            pcall(function() mulai_logcat_stream() end)   -- idempotent
            -- PID tiap client (biar tau disconnect dari client mana)
            local pidKe = {}
            for _, pkg in ipairs(split(cfg.pkgs or "")) do
                local nama = pkg:gsub("com%.roblox%.", "")
                local hp = io.popen("su -c 'pidof " .. pkg .. "' 2>/dev/null")
                local pids = hp and hp:read("*all") or ""
                if hp then hp:close() end
                for pid in pids:gmatch("%d+") do pidKe[pid] = nama end
            end
            pcall(function()
                local rejoinList = baca_logcat_stream(cfg, pidKe)
                for _, r in ipairs(rejoinList) do
                    local pkg = "com.roblox." .. r.nama
                    -- v7.35: JANGAN rejoin kode 285 (DisconnectClientInitiated) --
                    -- itu client KELUAR SENDIRI (backgrounding / worker navigate
                    -- ulang), BUKAN kick. Rejoin 285 = LOOP (rejoin->285->rejoin).
                    -- Cuma rejoin kalau kick ASLI (kode selain 285, misal 267).
                    -- Note: 267 (game kick) ternyata GAK muncul di logcat -- jadi
                    -- praktis ini jarang rejoin. Rejoin utama tetep jalur lain
                    -- (mati-mendadak/diem). Logcat cuma buat nangkep kick asli
                    -- kalau ADA + rekam history.
                    local kode285 = (r.kode == "285")
                    local baruDibuka = TERAKHIR_BUKA[pkg] and (now - TERAKHIR_BUKA[pkg]) < 40
                    if not kode285 and r.kode ~= "-"
                       and not KICK_DIURUS["captcha:" .. pkg] and not baruDibuka then
                        local ak = (mapAkun and mapAkun[pkg]) or r.nama
                        tambahLog(("[logcat] %s KICK kode %s -> REJOIN"):format(ak, r.kode))
                        open_one(cfg, pkg, mapLink and mapLink[pkg] or nil, "logcat-kick")
                    end
                end
            end)
        end
            end  -- v8.16: tutup if false (deteksi rejoin per-client dimatiin)

        end  -- v5.02: tutup 'if not lewatiRonde' (ronde bypass gak ngerjain sisanya)

        -- v4.18: keep-alive re-apply tiap 60 detik (Android suka reset oom_score_adj)
        if cfg.keep_alive ~= false and (now - lastKeepAlive) >= 60 then
            lastKeepAlive = now
            keep_alive_apply(cfg)
        end

        end  -- if not skip_sisa

        end  -- v6.35: tutup 'if not loginKelar' (LOGIN skip sisa ronde)

        os.execute("sleep "..cfg.poll_sec)
    end
end

-- ============================================================
-- v4.2: subperintah
--   lua5.4 velium_worker.lua          -> jalan
--   lua5.4 velium_worker.lua stop     -> berhenti baik-baik
--   lua5.4 velium_worker.lua status   -> jalan apa nggak
--   v4.78: key [link|refresh]       -> bypass key Delta lewat api.bypass.vip
--   v4.79: key set <APIKEY>         -> isi kunci API ke config (tanpa setup ulang)
-- ============================================================
-- v9.05: parse range "1-5"/"3"/"1,3,5" -> daftar pkg (GLOBAL, hemat lokal di
-- main chunk buat command home/game). cfg.pkgs urut, index 1-based.
function pkg_dari_range(cfg, rng)
    local semuaPkg = split(cfg.pkgs)
    local idxMau = {}
    local a, b = rng:match("^(%d+)%-(%d+)$")
    if a and b then
        for i = tonumber(a), tonumber(b) do idxMau[i] = true end
    elseif rng:find(",") then
        for n in rng:gmatch("%d+") do idxMau[tonumber(n)] = true end
    else
        local n = tonumber(rng)
        if n then idxMau[n] = true end
    end
    local pkgMau = {}
    for i, p in ipairs(semuaPkg) do
        if idxMau[i] then pkgMau[#pkgMau+1] = p end
    end
    return pkgMau, #semuaPkg
end

-- v9.05: jalanin muter game normal (GLOBAL, hemat lokal). Client di pkgMau muter
-- join game GAMES 5 menit tiap game -> akun tahan verif bot.
function jalankan_game_muter(pkgMau)
    local GAMES = {
        { id = "4924922222",      nama = "Brookhaven RP" },
        { id = "132678066262863", nama = "My Daycare" },
        { id = "13967668166",     nama = "LifeTogether RP" },
    }
    info(("GAME: %d client muter %d game normal (5menit/game). Ctrl+C buat stop."):format(#pkgMau, #GAMES))
    for gi, g in ipairs(GAMES) do
        info(("=== [%d/%d] %s (placeId=%s) -- tembak %d client, tahan 5 menit ==="):format(
            gi, #GAMES, g.nama, g.id, #pkgMau))
        local url = "roblox://placeId=" .. g.id
        for _, p in ipairs(pkgMau) do
            info("  " .. p:gsub("com%.roblox%.", "") .. " -> " .. g.nama)
            sh_silent("su -c 'am force-stop " .. p .. "'")
        end
        os.execute("sleep 2")
        for _, p in ipairs(pkgMau) do
            sh_silent("su -c \"am start -a android.intent.action.VIEW -d '" .. url .. "' -p " .. p .. "\"")
            os.execute("sleep 1")
        end
        ok(("  %d client ditembak ke %s. Tahan 5 menit..."):format(#pkgMau, g.nama))
        for _ = 1, 60 do os.execute("sleep 5") end
    end
    ok("GAME selesai: udah muter semua game. Balik ke GAG -> pencet Start/FORCE.")
end

-- v9.05: home sebagian client (GLOBAL). Force-stop + set grid.
function jalankan_home(cfg, pkgMau)
    -- v9.30: HOME = tembak client ke BROOKHAVEN + grid ukuran 6 CLIENT + CEK
    -- GRID BERULANG sampai pasti kepasang. User: home grid jadi ukuran 6 client,
    -- dan pastiin 6 client grid-nya (cek berulang sampai pasti). Caranya:
    -- PKGS_AKTIF isi pkgMau + PAD sampai minimal 6 -> grid_hitung petak ukuran 6.
    local BROOKHAVEN = "4924922222"
    local url = "roblox://placeId=" .. BROOKHAVEN
    info(("HOME: %d client -> tembak Brookhaven (1x) + grid ukuran 6 client. Out manual."):format(#pkgMau))
    -- bikin PKGS_AKTIF = pkgMau + pad (pkg cfg lain) sampai >=6
    local semuaPkg = split(cfg.pkgs)
    local aktif = {}
    local udah = {}
    for _, p in ipairs(pkgMau) do aktif[#aktif+1] = p; udah[p] = true end
    for _, p in ipairs(semuaPkg) do
        if #aktif >= 6 then break end
        if not udah[p] then aktif[#aktif+1] = p; udah[p] = true end
    end
    PKGS_AKTIF = aktif   -- >=6 -> grid_hitung petak ukuran 6 client
    GRID_CACHE = nil
    local petaGrid, gerr, gkol, gbar = grid_hitung(cfg, aktif)
    if not petaGrid then
        warn("GRID GAGAL dihitung: " .. tostring(gerr) .. " -- client tetep ditembak, grid dilewat")
    else
        info(("grid dihitung: %dx%d (ukuran %d client)"):format(gkol or 0, gbar or 0, #aktif))
    end
    -- v9.30: fungsi tulis+CEK grid 1 client sampai PASTI pas (max 3x).
    local function grid_pasti(pkg, kotak)
        -- v9.39: SIMPEL. User: gak masalah grid pas atau belum kebentuk, yg penting
        -- tembak. Dulu retry 3x + cek prefs berulang (baca L/T) -> client baru prefs
        -- kosong (L=nil) -> retry mubazir bermenit-menit. Sekarang tulis grid SEKALI
        -- aja (tata_satu), gak cek, gak retry. Kalau kepasang bagus, kalau nggak ya
        -- fullscreen (gak masalah -- client tetep kebuka).
        local nmp = pkg:gsub("com%.roblox%.", "")
        pcall(function() tata_satu(pkg, kotak, true) end)
        info(("    [grid] %s -> ditulis (%d,%d)"):format(nmp, kotak.L, kotak.T))
        return true
    end
    -- v9.37: TULIS GRID SEMUA CLIENT DULU (batch), BARU tembak. Fix user: home/
    -- masuk delay LAMA + ada yg belum ke-grid. Dulu per-client: force-stop -> grid
    -- retry 3x -> sleep -> tembak (4-6s/client x6 = 30s+). Sekarang: (1) force-stop
    -- semua, (2) tulis grid semua (retry per client tapi tanpa tembak di antaranya),
    -- (3) tembak semua barengan. Lebih cepet + grid pasti kepasang sebelum tembak.
    -- v9.53: BALIK ke PER-CLIENT (force-stop -> tulis grid -> tembak, satu-satu).
    -- User: grid ditulis TEPAT sebelum open lebih bagus -- App Cloner baca prefs
    -- FRESH pas app MULAI. Batch (tulis semua dulu, baru tembak semua) bikin grid
    -- gak keatur (prefs ketimpa/ke-cache sebelum app mulai). Per-client = grid pas.
    for _, p in ipairs(pkgMau) do
        local nmp = p:gsub("com%.roblox%.", "")
        -- 1. force-stop client ini (App Cloner baca prefs pas MATI/mulai)
        sh_silent("su -c 'am force-stop " .. p .. "'")
        os.execute("sleep 1")
        -- 2. tulis grid TEPAT sebelum open (prefs fresh)
        if petaGrid and petaGrid[p] then
            grid_pasti(p, petaGrid[p])
        else
            info("    (grid: " .. nmp .. " gak dapet posisi)")
        end
        -- 3. LANGSUNG tembak ke Brookhaven (App Cloner baca grid yg baru ditulis)
        info("  " .. nmp .. " -> Brookhaven")
        sh_silent("su -c \"am start -a android.intent.action.VIEW -d '" .. url .. "' -p " .. p .. "\"")
        os.execute("sleep 1")   -- jeda antar client
    end
    ok(("HOME selesai: %d client ditembak Brookhaven + grid ukuran 6. Out manual kalau mau."):format(#pkgMau))
end

PERINTAH = (arg and arg[1] or ""):lower()

-- v4.78: `velium key` -- salin link key-system Delta, terus jalanin ini.
--   velium key                -> ambil link dari clipboard (termux-clipboard-get)
--   velium key <link>         -> pakai link yang diketik
--   velium key refresh        -> link dari clipboard, tapi paksa proses ulang
--   velium key refresh <link> -> link diketik + paksa proses ulang
-- refresh JANGAN dipakai sembarangan -- itu ngelewatin hasil simpanan, buat
-- link yang emang sering ganti doang.
-- v4.84: `velium intip <client> [jeda]` -- potret teks di layar client, buat
-- nyocokin penanda (layar key / Home / error) ke tampilan ASLI, bukan tebakan.
--   velium intip              -> daftar client
--   velium intip clienu       -> potret sekarang (jeda bawaan 5 detik)
--   velium intip clienu 20    -> nunggu 20 detik dulu, baru dipotret
-- Jeda itu buat ngasih waktu lo mindahin layar ke keadaan yang mau direkam.
-- v4.87: `velium lisensi` -- liat keadaan kunci Delta + apa yang bakal worker
-- lakuin. Aman, cuma baca. Dipakai buat mastiin deteksinya bener tanpa harus
-- nunggu kuncinya beneran kedaluwarsa.
-- v4.88: `velium tap <client> <x> <y> [kali]` -- kalibrasi letak tombol.
-- x & y itu PECAHAN 0..1 dari kotak jendela (0.5 0.5 = tengah). Dipakai buat
-- nyari letak tombol "Copied link" di layar key Delta: coba, liat kepencet apa
-- nggak, geser angkanya, ulangi. Begitu ketemu, simpen di config:
--   key_tap="0.5,0.62"
-- Angka pecahan kepakai di SEMUA client -- petaknya beda-beda, ukurannya sama.
-- v4.90: `velium rekam <client> [detik]` -- lo yang pencet, worker yang nyatet.
-- Jauh lebih akurat daripada nebak-geser angka.
-- v4.97: `velium pantau <client> [detik]` -- TIAP kali lo pencet, koordinatnya
-- langsung nongol. Gak ada balapan sama waktu kayak `velium rekam`: pencet
-- sesukanya, liat angkanya, pilih sendiri yang bener.
-- v5.00: `velium cari <client>` -- worker nyari sendiri tombol key-nya, sampai
-- papan klip keisi link. Ketemu -> diinget buat ukuran jendela itu -> langsung
-- diproses jadi kunci Delta sekalian.
-- v5.11: `velium uji <client>` -- tembak beberapa titik menyebar sekaligus, buat
-- mastiin pencetannya NYAMPE ke client apa nggak. Gak butuh tau letak tombol:
-- kalau nyampe, PASTI ada yang bereaksi (papan ketik muncul / tombol nyala /
-- dialog ketutup / browser kebuka). Kalau nol reaksi dari semua titik, berarti
-- jalur pencetannya yang bermasalah -- dan nyapu 20 titik cuma buang waktu.
-- v5.15: `velium catat <client> <jumlah> [detik]` -- SATU perintah buat kalibrasi
-- manual: jendela diset ke ukuran N client, client dibuka ulang, terus LO yang
-- nunjukin tombolnya (tap beberapa kali). Rata-ratanya disimpen otomatis.
-- Bedanya sama `velium ukur`: itu worker yang nyapu nebak-nebak; ini lo yang
-- nunjukin -- jauh lebih cepet dan pasti.
-- v5.18: `velium set <client> <jumlah> [slot]` -- CUMA atur ukuran jendela ke
-- petak N client, terus buka ulang. Gak nyapu, gak minta tap.
-- Gunanya buat NGUJI: set ukuran lain, terus tembak pakai pecahan yang udah
-- ada (`velium tap`). Kalau kena juga, berarti satu angka cukup buat semua ukuran.
if PERINTAH == "daftar-cek" then
    -- v9.39: DIAGNOSTIK form daftar Roblox. Dump UI client (yg lagi di layar
    -- daftar), tampilin SEMUA field. BUNGKUS FUNGSI biar local gak numpuk di
    -- main chunk (batas 200 lokal -- v9.38 error "too many local variables").
    local function jalankan_daftar_cek()
        local cfg = load_config()
        if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end
        local rng = arg and arg[2] or ""
        if rng == "" then
            err("Cara pakai:  velium daftar-cek <client>")
            info("   contoh:  velium daftar-cek 1   -> dump UI form daftar client ke-1")
            info("   (buka Roblox sampai layar SIGN UP dulu, baru jalanin ini)")
            return
        end
        local pkgMau = pkg_dari_range(cfg, rng)
        if #pkgMau == 0 then err("Client '" .. rng .. "' gak ketemu."); return end
        local pkg = pkgMau[1]
        info("Dump UI form daftar: " .. pkg:gsub("com%.roblox%.", ""))
        local dump = (os.getenv("HOME") or "/data/data/com.termux/files/home") .. "/ui_daftar.xml"
        local isi = sh("su -c 'rm -f " .. dump .. "; uiautomator dump " .. dump ..
                       " >/dev/null 2>&1; cat " .. dump .. " 2>/dev/null; rm -f " .. dump .. "'") or ""
        if not isi:find("bounds", 1, true) then
            err("Dump UI gagal / kosong. Pastiin layar daftar Roblox kebuka + client di depan.")
            return
        end
        info("=== FIELD DI LAYAR (id / text / class / bounds) ===")
        local n = 0
        for simpul in isi:gmatch("<node[^>]*>") do
            local rid = simpul:match('resource%-id="([^"]*)"') or ""
            local txt = simpul:match('text="([^"]*)"') or ""
            local cls = simpul:match('class="([^"]*)"') or ""
            local bnd = simpul:match('bounds="([^"]*)"') or ""
            local editable = simpul:match('class="android%.widget%.EditText"')
            local clickable = simpul:match('clickable="true"')
            if editable or (clickable and txt ~= "") or (txt ~= "" and #txt < 40) then
                n = n + 1
                local tag = editable and "[INPUT]" or (clickable and "[TAP]" or "[teks]")
                info(("  %s id=%s | text=%q | %s | %s"):format(
                    tag,
                    (rid ~= "" and rid:gsub("^.*/", "") or "-"),
                    txt, bnd,
                    cls:gsub("^android%.widget%.", "")))
            end
        end
        info(("=== %d field ketemu ==="):format(n))
        info("Kirim hasil ini -- dari sini dibikin auto-isi (velium daftar).")
        info("[INPUT]=field ketik, [TAP]=tombol/dropdown. bounds=[x1,y1][x2,y2] (titik tap = tengah).")
    end
    jalankan_daftar_cek()
    return
end

if PERINTAH == "masuk" then
    -- v9.09: velium masuk -> scan SEMUA client, yang BELUM ADA AKUN (username kosong
    -- di prefs.xml) ditembak ke Brookhaven biar masuk Roblox (login screen).
    -- Terus user bisa masukin akun ke client itu manual. (nama 'cek'/'login' udah
    -- kepakai, jadi command ini namanya 'masuk'.)
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end
    local BROOKHAVEN = "4924922222"
    local url = "roblox://placeId=" .. BROOKHAVEN
    local semuaPkg = split(cfg.pkgs)
    local kosong = {}
    info(("Cek %d client -- cari yang belum ada akun..."):format(#semuaPkg))
    for i, p in ipairs(semuaPkg) do
        local u = baca_username(p)
        if not u or u == "" then
            kosong[#kosong+1] = p
            info(("  #%d %s -> BELUM ADA AKUN"):format(i, p:gsub("com%.roblox%.", "")))
        else
            info(("  #%d %s -> ada (%s)"):format(i, p:gsub("com%.roblox%.", ""), u))
        end
    end
    if #kosong == 0 then
        ok("Semua client udah ada akun. Gak ada yg perlu ditembak.")
        return
    end
    -- v9.150: BUKA 6 DOANG per jalan (grid selalu ukuran 6). Sisanya MANUAL:
    -- login dulu ke 6 ini -> username keisi -> `velium masuk` lagi otomatis nemu
    -- yg masih kosong berikutnya. Gak auto-sesi (user minta manual re-run).
    local BATCH = 6
    local batch = {}
    for i = 1, math.min(BATCH, #kosong) do batch[#batch+1] = kosong[i] end
    info(("Buka %d client (grid ukuran 6) -> Brookhaven..."):format(#batch))
    jalankan_home(cfg, batch)   -- pad ke min 6 -> grid selalu ukuran 6
    local sisa = #kosong - #batch
    if sisa > 0 then
        ok(("MASUK: %d client dibuka. Login ke 6 ini dulu, terus JALANIN `velium masuk` LAGI buat %d sisanya."):format(#batch, sisa))
    else
        ok(("MASUK selesai: %d client dibuka (semua yg kosong)."):format(#batch))
    end
    return
end

if PERINTAH == "game" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end
    local rng = arg and arg[2] or ""
    if rng == "" then
        err("Cara pakai:  velium game <range>")
        info("   contoh:  velium game 1-5   -> client ke-1..5 muter game normal 5menit/game")
        return
    end
    local pkgMau, total = pkg_dari_range(cfg, rng)
    if #pkgMau == 0 then err("Gak ada client di range '" .. rng .. "'. Total: " .. total); return end
    jalankan_game_muter(pkgMau)
    return
end

if PERINTAH == "home" then
    local cfg = load_config()
    if not cfg then
        err("Config belum ada. Path dicoba: " .. _config_paths_dicoba)
        info("  cwd sekarang: " .. (os.getenv("PWD") or "?") .. " | HOME: " .. (os.getenv("HOME") or "?"))
        return
    end
    local rng = arg and arg[2] or ""
    if rng == "" then
        err("Cara pakai:  velium home <range>")
        info("   contoh:  velium home 1-5   -> client ke-1..5 balik home + grid")
        info("            velium home 3     -> client ke-3 doang")
        info("            velium home 1,3,5 -> client ke-1,3,5")
        return
    end
    local pkgMau, total = pkg_dari_range(cfg, rng)
    if #pkgMau == 0 then err("Gak ada client di range '" .. rng .. "'. Total: " .. total); return end
    jalankan_home(cfg, pkgMau)
    return
end

if PERINTAH == "set" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end
    local target = arg and arg[2] or ""
    local jumlah = math.floor(tonumber(arg and arg[3] or "") or 0)
    local slot   = math.floor(tonumber(arg and arg[4] or "") or 1)
    if target == "" or jumlah < 1 then
        err("Cara pakai:  velium set <client> <jumlah-client> [slot]")
        info("   contoh:  velium set clienu 2    -> jendela jadi ukuran kalau 2 client")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config."); info("Yang ada: " .. cfg.pkgs); return
    end

    local petak, kol, bar, W, H = petak_untuk(jumlah, slot, cfg)
    if not petak then err("Gagal: " .. tostring(kol)); return end

    print(C.BOLD..C.C.."\n=== SET UKURAN buat " .. jumlah .. " CLIENT ==="..C.N)
    info(("Layar %dx%d, susunan %dx%d"):format(W, H, kol, bar))

    info(("Petak %d: [%d,%d]-[%d,%d]  ->  %dx%d"):format(
        slot, petak.L, petak.T, petak.R, petak.B, petak.R - petak.L, petak.B - petak.T))

    close_all(cfg, pkg, nil, true)
    os.execute("sleep 2")
    local tok, tket = tata_satu(pkg, petak)
    if not tok then err("Gagal nulis posisi: " .. tostring(tket)); return end
    ok("Posisi ketulis: " .. tket)
    open_one(cfg, pkg, nil, "cli-manual")
    for sisa = 40, 1, -1 do
        io.write(("\r   nunggu client nyala... %2ds"):format(sisa))
        io.flush(); os.execute("sleep 1")
    end
    io.write("\r" .. string.rep(" ", 45) .. "\r"); io.flush()

    local nyata = jendela_kotak(pkg)
    if nyata then
        ok(("Jendela sekarang: [%d,%d]-[%d,%d]  %dx%d"):format(
            nyata.L, nyata.T, nyata.R, nyata.B, nyata.R - nyata.L, nyata.B - nyata.T))
        local simpan = tap_muat()[("%dx%d"):format(nyata.R - nyata.L, nyata.B - nyata.T)]
        if simpan then
            info(("Ukuran ini UDAH kecatat: %.3f , %.3f"):format(simpan.fx, simpan.fy))
        else
            info("Ukuran ini BELUM kecatat.")
        end
    end
    print()
    info("Uji pakai pecahan dari ukuran lain:")
    info("   velium tap " .. target .. " 0.823 0.723 2 5")
    info("Terus cek papan klipnya:  velium key")
    print()
    return
end

if PERINTAH == "catat" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end
    local target = arg and arg[2] or ""
    local jumlah = math.floor(tonumber(arg and arg[3] or "") or 0)
    local detik  = math.floor(tonumber(arg and arg[4] or "") or 90)
    if target == "" or jumlah < 1 then
        err("Cara pakai:  velium catat <client> <jumlah-client> [detik]")
        info("   contoh:  velium catat clienu 10")
        info("            velium catat clienu 4 120")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config."); info("Yang ada: " .. cfg.pkgs); return
    end

    local petak, kol, bar, W, H = petak_untuk(jumlah, 1, cfg)
    if not petak then err("Gagal: " .. tostring(kol)); return end

    print(C.BOLD..C.C.."\n=== CATAT TOMBOL buat " .. jumlah .. " CLIENT ==="..C.N)
    info(("Layar %dx%d, susunan %dx%d -> petak %dx%d"):format(
        W, H, kol, bar, petak.R - petak.L, petak.B - petak.T))
    if bar >= 3 then
        info("Jendelanya pendek -- kalau susah nge-tap tangan, pakai sapuan otomatis:")
        info("   velium set " .. target .. " " .. jumlah .. "   lalu   velium cari " .. target)
    end

    info("Tutup client, tulis ukuran, buka lagi...")
    close_all(cfg, pkg, nil, true)
    os.execute("sleep 2")
    local tok, tket = tata_satu(pkg, petak)
    if not tok then err("Gagal nulis posisi: " .. tostring(tket)); return end
    open_one(cfg, pkg, nil, "cli-manual")
    for sisa = 40, 1, -1 do
        io.write(("\r   nunggu client nyala & layar key nongol... %2ds"):format(sisa))
        io.flush(); os.execute("sleep 1")
    end
    io.write("\r" .. string.rep(" ", 60) .. "\r"); io.flush()

    local kotak, sebabK = jendela_kotak(pkg)
    if not kotak then err("Gagal baca kotak jendela: " .. tostring(sebabK)); return end
    local lebar, tinggi = kotak.R - kotak.L, kotak.B - kotak.T
    local kunci = ("%dx%d"):format(lebar, tinggi)
    ok(("Jendela: [%d,%d]-[%d,%d]  %s"):format(kotak.L, kotak.T, kotak.R, kotak.B, kunci))

    local maxX = (select(1, layar_fisik()) > 0) and select(1, layar_fisik()) or W
    local maxY = (select(2, layar_fisik()) > 0) and select(2, layar_fisik()) or H

    local berkas = "/sdcard/velium_catat.txt"
    sh_silent("su -c 'rm -f " .. berkas .. "'")
    os.execute("su -c 'timeout " .. (detik + 20) .. " getevent -l > " .. berkas .. "' >/dev/null 2>&1 &")

    print()
    print(C.BOLD..C.Y.."   TAP TOMBOL 'Copied link' -- 3-5 kali"..C.N)
    print(C.D.."   jangan geser/ubah ukuran jendela sampai selesai."..C.N)
    print()

    -- v5.16: gak usah tap tengah dulu. Arah layar ditentuin dari TAP LO SENDIRI:
    -- dari dua arah yang mungkin (panel tegak, layar rebah), cuma satu yang bakal
    -- jatuh DI DALAM jendela. Jendelanya kecil dibanding layar, jadi hampir
    -- mustahil dua-duanya cocok -- dan kalau kebetulan cocok dua-duanya, tap itu
    -- dilewat aja, nunggu tap berikutnya yang jelas.
    local arahKunci, sudah, mulai = nil, 0, os.time()
    local kumpul = {}
    while (os.time() - mulai) < detik do
        if ada_stop() then break end
        os.execute("sleep 2")
        local isi = sh("su -c 'cat " .. berkas .. " 2>/dev/null'") or ""
        local xs, ys = {}, {}
        for n in isi:gmatch("ABS_MT_POSITION_X%s+(%x+)") do xs[#xs+1] = tonumber(n, 16) end
        for n in isi:gmatch("ABS_MT_POSITION_Y%s+(%x+)") do ys[#ys+1] = tonumber(n, 16) end
        local ada = math.min(#xs, #ys)
        for i = sudah + 1, ada do
            if not arahKunci then
                -- arah mana yang bikin tap ini jatuh di dalam jendela?
                local cocok = {}
                for _, c in ipairs(arah_calon(maxX, maxY, W, H)) do
                    local t = sentuh_ke_pecahan(xs[i], ys[i], maxX, maxY, W, H, kotak, c)
                    if t and t.didalam then cocok[#cocok+1] = { c = c, t = t } end
                end
                if #cocok == 1 then
                    arahKunci = cocok[1].c
                    ok("Arah layar terkunci: " .. arahKunci.nama)
                    kumpul[#kumpul+1] = { fx = cocok[1].t.fx, fy = cocok[1].t.fy }
                    print(("  %s#1  layar(%4d,%4d)  ->  %.3f , %.3f%s"):format(
                        C.G, cocok[1].t.X, cocok[1].t.Y, cocok[1].t.fx, cocok[1].t.fy, C.N))
                elseif #cocok > 1 then
                    -- dua-duanya cocok -> putusin lewat setelan putaran layar
                    local c, rot = arah_dari_rotasi(maxX, maxY, W, H)
                    if c then
                        arahKunci = c
                        ok(("Arah layar terkunci: %s (dari setelan putaran = %d)"):format(c.nama, rot or -1))
                        local t = sentuh_ke_pecahan(xs[i], ys[i], maxX, maxY, W, H, kotak, c)
                        if t and t.didalam then
                            kumpul[#kumpul+1] = { fx = t.fx, fy = t.fy }
                            print(("  %s#1  layar(%4d,%4d)  ->  %.3f , %.3f%s"):format(
                                C.G, t.X, t.Y, t.fx, t.fy, C.N))
                        end
                    else
                        print(C.D.."  --  arahnya ambigu, tap sekali lagi"..C.N)
                    end
                else
                    print(C.D.."  --  di LUAR jendela (abaikan)"..C.N)
                end
            else
                local t = sentuh_ke_pecahan(xs[i], ys[i], maxX, maxY, W, H, kotak, arahKunci)
                if t and t.didalam then
                    kumpul[#kumpul+1] = { fx = t.fx, fy = t.fy }
                    print(("  %s#%d  layar(%4d,%4d)  ->  %.3f , %.3f%s")
                        :format(C.G, #kumpul, t.X, t.Y, t.fx, t.fy, C.N))
                elseif t then
                    print(("  %s--  di LUAR jendela (abaikan)%s"):format(C.D, C.N))
                end
            end
        end
        sudah = ada
    end
    sh_silent("su -c 'rm -f " .. berkas .. "'")
    sh_silent("su -c 'pkill -9 getevent'")

    print()
    if #kumpul == 0 then
        err("Gak ada tap yang kecatat di dalam jendela.")
        info("Pastiin tap-nya di dalam jendela client, terus ulangi.")
        return
    end

    -- v5.19: JANGAN pakai rata-rata polos. Satu tap nyasar langsung narik
    -- hasilnya, dan rata-ratanya bisa jatuh di ANTARA dua elemen -- bukan di
    -- tombolnya. Gantinya: cari KELOMPOK TAP PALING RAPAT (yang Y-nya
    -- berdekatan), sisanya dibuang. Tombolnya panjang, jadi yang dipakai
    -- ngelompokin cuma Y; X-nya boleh nyebar.
    local RAPAT = 0.04   -- beda Y masih dianggap tombol yang sama
    local juara = {}
    for _, pusat in ipairs(kumpul) do
        local anggota = {}
        for _, k in ipairs(kumpul) do
            if math.abs(k.fy - pusat.fy) <= RAPAT then anggota[#anggota+1] = k end
        end
        if #anggota > #juara then juara = anggota end
    end

    local function ringkas(t)
        local sx, sy, minx, maxx, miny, maxy = 0, 0, 9, -9, 9, -9
        for _, k in ipairs(t) do
            sx = sx + k.fx; sy = sy + k.fy
            if k.fx < minx then minx = k.fx end
            if k.fx > maxx then maxx = k.fx end
            if k.fy < miny then miny = k.fy end
            if k.fy > maxy then maxy = k.fy end
        end
        return sx / #t, sy / #t, minx, maxx, miny, maxy
    end

    local _, _, amx, aax, amy, aay = ringkas(kumpul)
    info(("%d tap kecatat -- sebaran semua: x %.3f-%.3f | y %.3f-%.3f"):format(
        #kumpul, amx, aax, amy, aay))

    local rx, ry, kmx, kax, kmy, kay = ringkas(juara)
    if #juara < #kumpul then
        info(("%d tap nyasar dibuang, kepakai %d yang paling rapat"):format(
            #kumpul - #juara, #juara))
    end
    ok(("Hasil: %.3f , %.3f   (dari %d tap, sebaran y %.3f-%.3f)"):format(
        rx, ry, #juara, kmy, kay))

    if #juara < 2 then
        warn("Cuma 1 tap yang kepakai -- tap-tap lo kejauhan satu sama lain.")
        warn("Ulangi, pastiin nge-tap TOMBOL YANG SAMA tiap kali.")
    elseif (kay - kmy) > 0.05 then
        warn("Sebaran Y masih lebar -- hasilnya belum tentu pas di tombol.")
        warn("Uji dulu sebelum dipakai.")
    end

    if tap_simpan(kunci, rx, ry) then
        ok(("Kesimpen: %s -> %.3f , %.3f  (di %s)"):format(kunci, rx, ry, TAP_FILE))
    else
        err("Gagal nyimpen ke " .. TAP_FILE)
    end
    print()
    warn("CATATAN v7.53: velium_tap.txt GAK DIBACA lagi -- worker pakai tabel BAWAAN.")
    warn("Kalibrasi ini kesimpen tapi GAK KEPAKAI. Kalau titik bawaan meleset,")
    warn("kabarin buat diupdate di kode (biar gak kena salah-pencet velium catat).")
    info("Uji balik:  velium tap " .. target .. (" %.3f %.3f 2 5"):format(rx, ry))
    info("Ukuran lain:  velium catat " .. target .. " 6")
    info("Liat semua:  cat ~/" .. TAP_FILE)
    print()
    return
end

if PERINTAH == "uji" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end
    local target = arg and arg[2] or ""
    if target == "" then
        err("Cara pakai:  velium uji <client>")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config."); info("Yang ada: " .. cfg.pkgs); return
    end

    print(C.BOLD..C.C.."\n=== UJI PENCETAN ==="..C.N)
    local naik, siapa = pastikan_depan(pkg)
    if not naik then
        err("Gagal munculin client ke depan (yang di depan: " .. tostring(siapa) .. ")")
        if BAWA_SEBAB then info("Sebab: " .. BAWA_SEBAB) end
        return
    end
    local kotak, sebab = jendela_kotak(pkg)
    if not kotak then err("Gagal baca kotak jendela: " .. tostring(sebab)); return end
    ok(("Jendela: [%d,%d]-[%d,%d]  (%dx%d)"):format(
        kotak.L, kotak.T, kotak.R, kotak.B, kotak.R - kotak.L, kotak.B - kotak.T))
    print()
    print(C.BOLD..C.Y.."   LIATIN LAYAR CLIENT -- 6 titik ditembak berurutan"..C.N)
    print(C.D.."   Yang gua tanya cuma: ADA perubahan apa pun nggak?"..C.N)
    print()

    -- semua titik dikirim dalam SATU panggilan su -- tiap 'su' di RF ~6 detik,
    -- kalau satu-satu jadi lama banget dan susah diliatin.
    local titik = { {0.5,0.20}, {0.5,0.35}, {0.5,0.50}, {0.5,0.65}, {0.5,0.80}, {0.5,0.92} }
    local bagian = {}
    for _, t in ipairs(titik) do
        local x = math.floor(kotak.L + (kotak.R - kotak.L) * t[1])
        local y = math.floor(kotak.T + (kotak.B - kotak.T) * t[2])
        bagian[#bagian+1] = "input tap " .. x .. " " .. y
        info(("   titik %.2f -> layar (%d, %d)"):format(t[2], x, y))
    end
    sh("su -c '" .. table.concat(bagian, "; sleep 1.2; ") .. " 2>&1'")

    print()
    ok("Selesai -- 6 titik ketembak.")
    info("ADA reaksi (apa pun)  -> pencetan NYAMPE, lanjut:  velium cari " .. target)
    info("NOL reaksi semua      -> pencetan gak nyampe, kabarin gua")
    print()
    return
end

-- v5.06: `velium ukur <client> <jumlah> [slot]` -- pakai SATU client buat nyoba
-- ukuran jendela yang nanti kepakai kalau client-nya ada sekian.
-- Jendelanya diset ke ukuran itu, client dibuka ulang, terus tombol key-nya
-- dicari + disimpen. Jadi pas nanti beneran jalan 10 client, ukurannya udah
-- pernah dikenali -- gak usah nyapu lagi.
--   velium ukur clienu 4     -> ukuran kalau 4 client
--   velium ukur clienu 10    -> ukuran kalau 10 client
if PERINTAH == "ukur" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end

    local target = arg and arg[2] or ""
    local jumlah = math.floor(tonumber(arg and arg[3] or "") or 0)
    local slot   = math.floor(tonumber(arg and arg[4] or "") or 1)
    if target == "" or jumlah < 1 then
        err("Cara pakai:  velium ukur <client> <jumlah-client> [slot]")
        info("   contoh:  velium ukur clienu 4     -> ukuran kalau nanti 4 client")
        info("            velium ukur clienu 10    -> ukuran kalau nanti 10 client")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config.")
        info("Yang ada: " .. cfg.pkgs)
        return
    end

    local kotak, kol, bar, W, H = petak_untuk(jumlah, slot, cfg)
    if not kotak then err("Gagal: " .. tostring(kol)); return end
    local lebar, tinggi = kotak.R - kotak.L, kotak.B - kotak.T

    print(C.BOLD..C.C.."\n=== UKUR BUAT " .. jumlah .. " CLIENT ==="..C.N)
    info(("Layar   : %dx%d   susunan %dx%d"):format(W, H, kol, bar))
    info(("Petak %d : [%d,%d]-[%d,%d]  ->  %dx%d"):format(
        slot, kotak.L, kotak.T, kotak.R, kotak.B, lebar, tinggi))
    print()

    -- App Cloner baca posisi jendela pas app MULAI, dan nimpa balik pas app
    -- DITUTUP. Jadi urutannya harga mati: tutup -> tulis -> buka.
    info("Tutup client dulu...")
    close_all(cfg, pkg, nil, true)
    os.execute("sleep 2")

    info("Tulis ukuran jendela ke prefs App Cloner...")
    local tok, tket = tata_satu(pkg, kotak)
    if not tok then
        err("Gagal nulis posisi: " .. tostring(tket))
        info("(prefs baru kebentuk kalau client-nya pernah dibuka sekali)")
        return
    end
    ok("Posisi ketulis: " .. tket)

    info("Buka lagi client-nya...")
    open_one(cfg, pkg, nil, "cli-manual")

    -- tungguin dia nyala + nyampe layar key
    local tunggu = 45
    for sisa = tunggu, 1, -1 do
        io.write(("\r   nunggu client nyala & nampilin layar key... %2ds"):format(sisa))
        io.flush()
        os.execute("sleep 1")
    end
    io.write("\r" .. string.rep(" ", 60) .. "\r"); io.flush()

    -- pastiin ukurannya beneran kepakai
    local nyata = jendela_kotak(pkg)
    if nyata then
        local nl, nt = nyata.R - nyata.L, nyata.B - nyata.T
        if math.abs(nl - lebar) > 8 or math.abs(nt - tinggi) > 8 then
            warn(("Jendelanya jadi %dx%d, bukan %dx%d -- App Cloner gak nurut?"):format(
                nl, nt, lebar, tinggi))
            info("Lanjut aja, yang dipakai ukuran NYATA-nya.")
        else
            ok(("Jendela sekarang: [%d,%d]-[%d,%d]  %dx%d  (sesuai)"):format(
                nyata.L, nyata.T, nyata.R, nyata.B, nl, nt))
        end
    end

    print()
    info("Sekarang cari tombol key-nya...")
    local link, fx, fy, ket = cari_tombol_key(cfg, pkg)
    if not link then
        err("Gagal: " .. tostring(ket))
        info("Pastiin client-nya emang lagi minta key (lisensi udah dihapus?).")
        return
    end
    ok(("Ketemu!  %s"):format(ket))
    ok(("Titik tombol: %.3f , %.3f  -- kesimpen di %s"):format(fx, fy, TAP_FILE))
    print()
    info("Ulangi buat ukuran lain:  velium ukur " .. target .. " 6")
    info("Liat semua yang udah kesimpen:  cat ~/" .. TAP_FILE)
    print()

    -- link-nya sekalian dipakai, sayang kalau kebuang
    info("Sekalian diproses jadi kunci...")
    local kunci, sebab = bypass_kunci(cfg, link, false)
    if kunci then
        ok("KUNCI: " .. kunci)
        local wok, wket = tulis_lisensi(cfg, kunci)
        if wok then ok("Ditulis ke Delta: " .. wket)
        else warn("Gagal nulis lisensi: " .. tostring(wket)) end
    else
        warn("Bypass gagal: " .. tostring(sebab))
    end
    print()
    return
end

if PERINTAH == "cari" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end

    local target = arg and arg[2] or ""
    if target == "" then
        err("Cara pakai:  velium cari <client>")
        info("   contoh:  velium cari clienu")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config.")
        info("Yang ada: " .. cfg.pkgs)
        return
    end

    print(C.BOLD..C.C.."\n=== CARI TOMBOL KEY ==="..C.N)
    do
        local kead, umur = lisensi_keadaan(cfg)
        info("Lisensi sekarang: " .. kead ..
             (umur and ("  (umur " .. umur_ringkas(umur) .. ")") or ""))
    end
    info("Nyoba beberapa titik, tiap kali diperiksa papan klipnya.")
    info("Bisa makan beberapa menit -- jangan disentuh dulu.")
    print()

    local link, fx, fy, ket = cari_tombol_key(cfg, pkg)
    if not link then
        err("Gagal: " .. tostring(ket))
        info("Kemungkinan: layar key lagi gak nongol, atau tombolnya di luar garis tengah.")
        info("Pastiin client-nya emang lagi minta key, terus coba lagi.")
        return
    end

    ok(("Dapet link!  [%s]"):format(ket))
    ok(("Titik tombol: %.3f , %.3f  -- diinget di %s"):format(fx, fy, TAP_FILE))
    info("Link: " .. link:sub(1, 55) .. "...")
    print()

    info("Proses ke API bypass... (30-60 detik)")
    local kunci, sebab, mentah = bypass_kunci(cfg, link, false)
    if not kunci then
        err("Bypass gagal: " .. tostring(sebab))
        if mentah and mentah:gsub("%s+", "") ~= "" then
            info("Jawaban mentah API:")
            print(C.D .. mentah:sub(1, 400) .. C.N)
        end
        return
    end
    ok("KUNCI: " .. kunci)

    local wok, wket = tulis_lisensi(cfg, kunci)
    if wok then
        ok("Ditulis ke Delta: " .. wket)
        info("Kepakai SEMUA client. Restart client yang minta key:")
        info("   su -c 'am force-stop " .. pkg .. "'")
    else
        warn("Gagal nulis ke Delta: " .. tostring(wket))
    end
    print()
    return
end

if PERINTAH == "pantau" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end

    local target = arg and arg[2] or ""
    local detik = math.floor(tonumber(arg and arg[3] or "") or 120)
    if target == "" then
        err("Cara pakai:  velium pantau <client> [detik]")
        info("   contoh:  velium pantau clienu 120")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config.")
        info("Yang ada: " .. cfg.pkgs)
        return
    end

    print(C.BOLD..C.C.."\n=== PANTAU SENTUHAN ==="..C.N)
    info("Bawa " .. pkg:gsub("com%.roblox%.","") .. " ke depan (tanpa link join)...")
    bawa_depan(pkg)
    os.execute("sleep 3")

    local kotak, sebabK = jendela_kotak(pkg)
    if not kotak then err("Gagal baca kotak jendela: " .. tostring(sebabK)); return end
    ok(("Jendela: [%d,%d]-[%d,%d]  (%dx%d)"):format(
        kotak.L, kotak.T, kotak.R, kotak.B, kotak.R - kotak.L, kotak.B - kotak.T))

    local W, H = layar_ukuran()
    local fW, fH = layar_fisik()
    local maxX = (fW > 0) and fW or W
    local maxY = (fH > 0) and fH or H

    local berkas = "/sdcard/velium_pantau.txt"
    sh_silent("su -c 'rm -f " .. berkas .. "'")
    -- getevent jalan di latar, nulis ke berkas. Kita baca berkalanya.
    os.execute("su -c 'timeout " .. detik .. " getevent -l > " .. berkas .. "' >/dev/null 2>&1 &")

    -- v4.98: LANGKAH 1 -- kunci arah putaran pakai patokan.
    local tengahX = (kotak.L + kotak.R) / 2
    local tengahY = (kotak.T + kotak.B) / 2
    print()
    print(C.BOLD..C.Y.."   LANGKAH 1: TAP TEPAT DI TENGAH JENDELA CLIENT"..C.N)
    -- v4.99: dibulatin dulu -- (124+1153)/2 = 638.5, dan %d nolak bilangan pecahan
    print(C.D..("   (kira-kira aja, buat ngunci arah layar. tengahnya di %d,%d)")
        :format(math.floor(tengahX), math.floor(tengahY))..C.N)
    print()

    local arahKunci, sudah, mulai = nil, 0, os.time()
    while (os.time() - mulai) < detik do
        if ada_stop() then info("dihentikan (velium stop)"); break end   -- v5.14
        os.execute("sleep 2")
        local isi = sh("su -c 'cat " .. berkas .. " 2>/dev/null'") or ""
        local xs, ys = {}, {}
        for n in isi:gmatch("ABS_MT_POSITION_X%s+(%x+)") do xs[#xs+1] = tonumber(n, 16) end
        for n in isi:gmatch("ABS_MT_POSITION_Y%s+(%x+)") do ys[#ys+1] = tonumber(n, 16) end
        local ada = math.min(#xs, #ys)

        for i = sudah + 1, ada do
            if not arahKunci then
                -- sentuhan pertama = patokan
                local pilih, jarak = kunci_arah(xs[i], ys[i], maxX, maxY, W, H, tengahX, tengahY)
                arahKunci = pilih
                ok("Arah layar terkunci: " .. pilih.nama ..
                   ("  (meleset %.0f px dari tengah)"):format(jarak))
                print()
                print(C.BOLD..C.Y.."   LANGKAH 2: SEKARANG TAP TOMBOLNYA -- boleh berkali-kali"..C.N)
                print(C.D.."   JANGAN geser/ubah ukuran jendela sampai selesai."..C.N)
                print()
            else
                local t = sentuh_ke_pecahan(xs[i], ys[i], maxX, maxY, W, H, kotak, arahKunci)
                if t and t.didalam then
                    print(("  %s#%d  layar(%4d,%4d)  ->  PECAHAN %.3f , %.3f%s")
                        :format(C.G, i, t.X, t.Y, t.fx, t.fy, C.N))
                elseif t then
                    print(("  %s#%d  layar(%4d,%4d)  -> di LUAR jendela (abaikan)%s")
                        :format(C.D, i, t.X, t.Y, C.N))
                end
            end
        end
        sudah = ada
    end

    sh_silent("su -c 'rm -f " .. berkas .. "'")
    print()
    if sudah == 0 then
        warn("Gak ada sentuhan kerekam sama sekali.")
    else
        info("Selesai. Ambil PECAHAN dari baris yang pas, terus simpen di config:")
        info('   key_tap="<x>,<y>",')
        info("Uji dulu:  velium tap " .. target .. " <x> <y> 2 5")
    end
    print()
    return
end

if PERINTAH == "rekam" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end

    local target = arg and arg[2] or ""
    -- v4.91: bawaan 30 detik (dulu 15). Kudu cukup buat baca tulisannya, geser
    -- ke jendela client, terus mencet -- 15 detik kesempitan.
    local detik = math.floor(tonumber(arg and arg[3] or "") or 30)
    if target == "" then
        err("Cara pakai:  velium rekam <client> [detik]")
        info("   contoh:  velium rekam clienu 20")
        return
    end
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config.")
        info("Yang ada: " .. cfg.pkgs)
        return
    end

    print(C.BOLD..C.C.."\n=== REKAM SENTUHAN ==="..C.N)
    info("Bawa " .. pkg:gsub("com%.roblox%.","") .. " ke depan (tanpa link join)...")
    bawa_depan(pkg)
    os.execute("sleep 3")

    local kotak, sebabK = jendela_kotak(pkg)
    if not kotak then err("Gagal baca kotak jendela: " .. tostring(sebabK)); return end
    ok(("Jendela: [%d,%d]-[%d,%d]  (%dx%d)"):format(
        kotak.L, kotak.T, kotak.R, kotak.B, kotak.R - kotak.L, kotak.B - kotak.T))
    print()
    print(C.BOLD..C.Y.."   >>> PENCET TOMBOLNYA SEKARANG <<<"..C.N)
    print(C.D..("   direkam " .. detik .. " detik. Geser ke jendela client, pencet SEKALI.")..C.N)
    print()

    local hasil, sebab = rekam_sentuh(pkg, kotak, detik)
    if not hasil then
        err("Gagal: " .. tostring(sebab))
        info("Coba lagi, pastiin mencetnya di dalam jendela client itu.")
        return
    end

    ok(("Kerekam di layar (%d, %d)  [arah: %s]"):format(hasil.X, hasil.Y, hasil.cara))
    if hasil.total and hasil.total > 1 then
        info(("   dari %d sentuhan, yang kepakai sentuhan ke-%d (yang jatuh di jendela)")
            :format(hasil.total, hasil.keBerapa or 1))
    end
    ok(("PECAHAN-nya: %.3f , %.3f"):format(hasil.fx, hasil.fy))
    print()
    info("Uji balik -- harusnya kepencet tombol yang sama:")
    info(("   velium tap %s %.3f %.3f 2 5"):format(target, hasil.fx, hasil.fy))
    print()
    info("Kalau bener, simpen di velium_worker_config.lua:")
    info(('   key_tap="%.3f,%.3f",'):format(hasil.fx, hasil.fy))
    print()
    return
end

-- v7.74: `velium buka <client>` -- TES SEMUA CARA MASUKIN 1 client, jeda 10s tiap
-- cara. Biar user liat sendiri cara mana yang BERHASIL masuk + GAK ganggu client
-- lain. Tiap cara dikasih nomor + nama, jeda 10s biar sempet diliat.
-- v8.17: `velium grid` -- cek UKURAN JENDELA tiap client vs grid target. Nampilin
-- mana yang meleset (masih besar / gak ke-grid). `velium grid fix` -> perbaiki:
-- tulis prefs + rejoin CUMA yang meleset (satu-satu, jeda) biar App Cloner
-- re-baca prefs. Client yang udah pas GAK diganggu.
--
-- KENAPA perlu: grid awal cuma TULIS prefs (gak force-stop) -- App Cloner cuma
-- baca prefs pas window DIBUKA. Client yang udah kebuka + gak pernah rejoin =
-- prefs udah bener TAPI window belum re-baca -> tetep besar. Ini yang mancing
-- "beberapa RF grid tetep besar". Fix = paksa client itu re-launch (rejoin)
-- biar baca prefs baru.
if PERINTAH == "dpi" then
    -- v8.20: atur DPI cloud phone (wm density). Buat hemat RAM/enteng di banyak
    -- VM. Pakai shell root persistent.
    --   velium dpi              -> baca DPI sekarang
    --   velium dpi <angka>      -> set DPI (mis 160/200/240). makin kecil = enteng
    --   velium dpi reset        -> balik ke DPI bawaan
    --   velium dpi auto         -> set ke 160 (hemat multi-VM)
    if not shell_nyalakan() then
        err("Shell root gak nyala. Cek RF udah rooted + izin su.") return
    end
    local sub = (arg and arg[2] or ""):lower()

    if sub == "" then
        local out = shell_jalan("wm density", 6) or ""
        info("=== DPI CLOUD PHONE ===")
        print(out ~= "" and ("  " .. out:gsub("\n", "\n  ")) or "  (gak kebaca)")
        print("")
        print("  set:   velium dpi 160   (makin kecil = enteng)")
        print("  reset: velium dpi reset")
        print("  auto:  velium dpi auto  (= 127, tampilan kecil)")
        return

    elseif sub == "reset" then
        shell_jalan("wm density reset", 8)
        os.execute("sleep 1")
        local out = shell_jalan("wm density", 6) or ""
        info("DPI di-reset ke bawaan.")
        print("  " .. out:gsub("\n", "\n  "))
        return

    else
        local nilai
        if sub == "auto" then nilai = 127
        else nilai = tonumber(sub) end
        if not nilai or nilai < 80 or nilai > 640 then
            err("DPI harus angka 80-640 (mis 160/200/240), atau 'reset'/'auto'.") return
        end
        shell_jalan("wm density " .. math.floor(nilai), 8)
        os.execute("sleep 1")
        local out = shell_jalan("wm density", 6) or ""
        info("DPI diset ke " .. math.floor(nilai) .. ".")
        print("  " .. out:gsub("\n", "\n  "))
        print("")
        print("  (kalau tampilan aneh, `velium dpi reset` buat balikin)")
        return
    end
end

if PERINTAH == "grid" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu.") return end
    if cfg.auto_grid ~= true then
        err("auto_grid MATI di config. Nyalain dulu (velium set auto_grid).") return
    end
    local pkgs = split(cfg.pkgs or "")
    if #pkgs == 0 then err("Gak ada client di config.") return end
    local fixMode = (arg and arg[2] == "fix")
    info("=== CEK GRID SEMUA CLIENT ===")
    -- hitung grid target (kotak tiap client yg SEHARUSNYA)
    local peta, sebabGrid, kol, bar, W, H = grid_hitung(cfg)
    if not peta then err("gagal hitung grid: " .. tostring(sebabGrid)) return end
    info(("Layar %sx%s, grid %sx%s. Target petak: %d x %d px")
        :format(tostring(W), tostring(H), tostring(kol), tostring(bar),
                math.floor((W or 0)/(kol or 1)), math.floor((H or 0)/(bar or 1))))
    print("")
    -- cuma cek client yang JALAN
    local aktif = {}
    for _, pkg in ipairs(pkgs) do if pkg_running(pkg) then aktif[#aktif+1] = pkg end end
    if #aktif == 0 then err("gak ada client jalan.") return end
    -- toleransi: window dianggap "meleset" kalau lebar/tinggi beda > 20% dari target
    local TOLERANSI = 0.20
    local meleset = {}
    for _, pkg in ipairs(aktif) do
        local nama = pkg:gsub("com%.roblox%.", "")
        local tgt = peta[pkg]
        if not tgt then
            print(("  %s%-8s  (gak ada di peta grid)%s"):format(C.D, nama, C.N))
        else
            local tgtW = (tgt.R or 0) - (tgt.L or 0)
            local tgtH = (tgt.B or 0) - (tgt.T or 0)
            -- bawa client ke depan dulu (biar jendela_kotak ukur yg bener)
            bawa_depan(pkg); os.execute("sleep 1")
            local kotak, sebabK = jendela_kotak(pkg)
            if not kotak then
                print(("  %s%-8s  gak keukur (%s)%s"):format(C.Y, nama, tostring(sebabK or "?"), C.N))
            else
                local aktW = (kotak.R or 0) - (kotak.L or 0)
                local aktH = (kotak.B or 0) - (kotak.T or 0)
                -- beda relatif lebar/tinggi
                local dW = tgtW > 0 and math.abs(aktW - tgtW) / tgtW or 1
                local dH = tgtH > 0 and math.abs(aktH - tgtH) / tgtH or 1
                if dW > TOLERANSI or dH > TOLERANSI then
                    print(("  %s%-8s  aktual %dx%d  target %dx%d  <- MELESET%s")
                        :format(C.R, nama, aktW, aktH, tgtW, tgtH, C.N))
                    meleset[#meleset+1] = pkg
                else
                    print(("  %s%-8s  aktual %dx%d  target %dx%d  ok%s")
                        :format(C.G, nama, aktW, aktH, tgtW, tgtH, C.N))
                end
            end
        end
    end
    print("")
    if #meleset == 0 then
        info("Semua client grid-nya udah pas. Gak ada yang perlu diperbaiki.")
        return
    end
    info(("%d client MELESET: %s"):format(#meleset,
        table.concat((function() local t = {} for _, p in ipairs(meleset) do
            t[#t+1] = p:gsub("com%.roblox%.", "") end return t end)(), ", ")))
    if not fixMode then
        print("")
        info("Buat perbaiki (tulis prefs + rejoin yang meleset): `velium grid fix`")
        info("(Cuma yang meleset yang di-rejoin, satu-satu + jeda. Yang pas aman.)")
        return
    end
    -- FIX: tulis prefs + rejoin yang meleset, SATU-SATU + jeda (biar gak mati bareng)
    print("")
    info("=== PERBAIKI GRID (rejoin yang meleset satu-satu) ===")
    -- ambil link PS per client dari panel (biar rejoin masuk ke PS yg bener).
    -- kalau gagal, open_one pakai link default cfg (tetep jalan -- link nil).
    local mapLink = {}
    pcall(function()
        local akun2pkg = {}
        for _, pkg in ipairs(aktif) do
            local u = baca_username(pkg)
            if u then akun2pkg[u] = pkg end
        end
        local r = api_get(cfg, "/assign-ps?tim=" .. cfg.tim)
        if r then
            for obj in tostring(r):gmatch("{(.-)}") do
                local ak = obj:match('"akun"%s*:%s*"(.-)"')
                local lk = obj:match('"link"%s*:%s*"(.-)"')
                if ak and lk and akun2pkg[ak] then mapLink[akun2pkg[ak]] = lk end
            end
        end
    end)
    for i, pkg in ipairs(meleset) do
        local nama = pkg:gsub("com%.roblox%.", "")
        info(("[%d/%d] %s -> tulis prefs + rejoin"):format(i, #meleset, nama))
        -- tulis prefs posisi grid dulu
        if peta[pkg] then
            local ok, ket = tata_satu(pkg, peta[pkg], true)   -- v8.81: hapus lama dulu
            info(("   prefs: %s%s"):format(ok and "ok" or "GAGAL ", tostring(ket or "")))
        end
        -- rejoin client ini (open_one re-launch -> App Cloner baca prefs baru)
        open_one(cfg, pkg, mapLink[pkg], "grid-fix")
        info("   rejoin dikirim, jeda 8s...")
        os.execute("sleep 8")   -- jeda antar client: hindari mati bareng
    end
    print("")
    info("Selesai. Cek ulang: `velium grid` (tunggu ~30s biar client kebuka penuh).")
    return
end

-- v7.88: `velium grafis` -- cek grafis SEMUA client sekaligus (1 su call). Nampilin
-- grafis MB + status (di game / out) tiap client. Cepet (gak per-client).
if PERINTAH == "grafis" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu.") return end
    local pkgs = split(cfg.pkgs or "")
    if #pkgs == 0 then err("Gak ada client di config.") return end
    info("=== CEK GRAFIS SEMUA CLIENT (1 su call) ===")
    -- v7.89: delay dulu (user minta) -- pas ketik command, Termux ke depan ->
    -- client ke Home. Delay biar USER SENDIRI yang arahin client ke depan
    -- (manual), gak pakai jaga_depan otomatis. Countdown biar keliatan sisa waktu.
    local jeda = math.floor(tonumber(arg and arg[2] or "") or 10)
    if jeda > 0 then
        info(("Arahin client ke depan sekarang -- cek grafis %ds lagi:"):format(jeda))
        for i = jeda, 1, -1 do
            io.write(("\r   %ds ...   "):format(i)); io.flush()
            os.execute("sleep 1")
        end
        io.write("\r            \n")
    end
    info("Ambang di game: >= 30 MB (game ~30-49, home ~15, out <2)")
    print("")
    local peta = grafis_semua(pkgs)
    local diGame, out = 0, 0
    for _, pkg in ipairs(pkgs) do
        local kb = peta[pkg] or 0
        local mb = kb / 1024
        local nama = pkg:gsub("com%.roblox%.", "")
        local status, warna
        if kb >= GAME_AMBANG_KB then
            status = "DI GAME"; warna = C.G; diGame = diGame + 1
        elseif kb >= 5 * 1024 then
            status = "home/loading"; warna = C.Y; out = out + 1
        else
            status = "OUT/mati"; warna = C.D; out = out + 1
        end
        print(("  %s%-8s  %6.0f MB   %s%s"):format(warna, nama, mb, status, C.N))
    end
    print("")
    info(("Total: %d di game, %d out/home (dari %d client)"):format(diGame, out, #pkgs))
    return
end

if PERINTAH == "buka" and not tonumber(arg and arg[2] or "") then
    -- (arg ANGKA -> tes buka N client, ditangani di blok `buka N` sebelum pasang)
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu.") return end
    local target = arg and arg[2] or ""
    if target == "" then
        err("Cara pakai:  velium buka <client>   (buka 1 client, kalibrasi)")
        info("      atau:  velium buka <N>        (TES buka N client loop utama, mis: velium buka 15)")
        info("   contoh:  velium buka clienp")
        return
    end
    local pkg = target:find("^com%.roblox%.") and target or ("com.roblox." .. target)
    local nama = pkg:gsub("com%.roblox%.", "")

    -- v7.76: ambil AKUN + LINK PS client ini (biar masuk GAG 2 beneran, bukan
    -- tembak kosong). akun dari baca_username, link PS dari /ps-list backend.
    local akun = baca_username(pkg) or ""
    local linkClient = nil
    if akun ~= "" then
        local r = api_get(cfg, "/ps-list") or ""
        for obj in r:gmatch('{.-}') do
            local a = obj:match('"akun"%s*:%s*"(.-)"')
            local psl = obj:match('"ps_link"%s*:%s*"(.-)"')
            if a == akun and psl and psl ~= "" then linkClient = psl break end
        end
    end
    local url = build_url(cfg, linkClient)
    info(("Akun: %s  |  link: %s"):format(akun ~= "" and akun or "(gak kebaca)",
        linkClient or "public/default"))

    -- v7.96: ekstrak accessCode/code dari linkClient (buat coba format WEB link
    -- kayak Hip Hub/Pandora: https://roblox.com/share?code=... atau games/start).
    local pid = cfg.place_id or "129343810645058"
    local kode = nil
    if linkClient then
        kode = linkClient:match("accessCode=([%w%-]+)")
            or linkClient:match("privateServerLinkCode=([%w%-]+)")
            or linkClient:match("code=([%w%-]+)")
            or linkClient:match("([%x][%x][%x][%x][%x][%x][%x][%x]+)")
    end
    local webShare = kode and ("https://www.roblox.com/share?code="..kode.."&type=Server") or ("https://www.roblox.com/games/"..pid)
    local webStart = kode and ("https://www.roblox.com/games/start?placeId="..pid.."&accessCode="..kode) or ("https://www.roblox.com/games/"..pid)
    local webPriv  = kode and ("https://www.roblox.com/games/"..pid.."?privateServerLinkCode="..kode) or ("https://www.roblox.com/games/"..pid)

    -- daftar CARA MASUKIN (dicoba satu-satu, jeda 10s). Fokus variasi CARA
    -- PANDORA (cmp ActivityProtocolLaunch + flag beda) + beberapa alternatif.
    -- am start -S (stop activity) DIBUANG -- ngerusak (user konfirmasi).
    local cara = {
        -- === CARA T: hapus task lama DULU, baru A3 (MULTIPLE_TASK) -- biar isolasi
        -- MULTIPLE_TASK dapet TAPI task gak numpuk (bug A3). am stack/task remove
        -- hapus task lama (window/activity) tanpa force-stop proses (lebih ringan).
        { n = "T", ket = "hapus task lama + MULTIPLE_TASK (fix bug A3 numpuk)",
          cmd = "for t in $(am stack list 2>/dev/null | grep -o 'taskId=[0-9]*' | grep -o '[0-9]*'); do am stack info $t 2>/dev/null | grep -q "..pkg.." && am task remove $t 2>/dev/null; done; sleep 1; am start -a android.intent.action.VIEW -d '"..url.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x18000000" },
        { n = "T2", ket = "am stack remove pkg + A3 MULTIPLE_TASK (cara lain hapus task)",
          cmd = "am stack remove "..pkg.." 2>/dev/null; sleep 1; am start -a android.intent.action.VIEW -d '"..url.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x18000000" },
        -- === CARA PANDORA PERSIS (dari logcat: -p pkg + -n cmp + flag 0x10000000) ===
        -- === CARA WEB (Hip Hub/Pandora style: -S + web URL) ===
        -- === CARA WEB TANPA -S (user gak mau -S/out) ===
        -- Web URL (gacor, gak nyangkut Home) TAPI pakai NEW_TASK biasa, BUKAN -S.
        -- -S = stop activity dulu (ada "out"). WN/WSN gak stop apa-apa: web URL
        -- + NEW_TASK (one task) -> masuk fresh tanpa out. Client lain aman (gak
        -- ada -S/force-stop yg goyangin service).
        { n = "WN", ket = "WEB games/start + NEW_TASK (TANPA -S): -p pkg -f 0x10000000",
          cmd = "am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -f 0x10000000" },
        { n = "WSN", ket = "WEB share + NEW_TASK (TANPA -S): -p pkg -f 0x10000000",
          cmd = "am start -a android.intent.action.VIEW -d '"..webShare.."' -p "..pkg.." -f 0x10000000" },
        { n = "WNP", ket = "WEB games/start + -n cmp + NEW_TASK (TANPA -S)",
          cmd = "am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10000000" },
        -- Reset activity Home TANPA -S: flag CLEAR_TOP(0x04000000) / CLEAR_TASK
        -- (0x00008000, butuh NEW_TASK) / RESET_IF_NEEDED(0x00200000). Ini "nge-reset"
        -- activity lama biar deep link ke-proses fresh, tapi BUKAN -S (gak stop
        -- app), jadi harusnya gak goyangin client lain.
        { n = "WC", ket = "WEB + NEW_TASK|CLEAR_TOP (0x14000000) TANPA -S -- reset activity",
          cmd = "am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -f 0x14000000" },
        { n = "WCT", ket = "WEB + NEW_TASK|CLEAR_TASK (0x10008000) TANPA -S -- task fresh",
          cmd = "am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -f 0x10008000" },
        { n = "WR", ket = "WEB + NEW_TASK|RESET_IF_NEEDED (0x10200000) TANPA -S",
          cmd = "am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -f 0x10200000" },
        { n = "WCC", ket = "WEB + -n cmp + NEW_TASK|CLEAR_TOP (0x14000000) TANPA -S",
          cmd = "am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x14000000" },
        -- Hapus task Home DULU (am task remove) baru web NEW_TASK -- TANPA -S,
        -- TANPA force-stop. Task Home dibuang -> tembak web -> masuk fresh.
        { n = "WT", ket = "hapus task DULU + WEB NEW_TASK (TANPA -S, TANPA force-stop)",
          cmd = "for t in $(am stack list 2>/dev/null | grep -o 'taskId=[0-9]*' | grep -o '[0-9]*'); do am stack info $t 2>/dev/null | grep -q "..pkg.." && am task remove $t 2>/dev/null; done; sleep 3; am start -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg.." -f 0x10000000" },
        { n = "W", ket = "WEB SHARE + -S (Hip Hub persis): share?code=...&type=Server",
          cmd = "am start -S -a android.intent.action.VIEW -d '"..webShare.."' -p "..pkg },
        { n = "WS", ket = "WEB games/start + -S: games/start?placeId=X&accessCode=Y",
          cmd = "am start -S -a android.intent.action.VIEW -d '"..webStart.."' -p "..pkg },
        { n = "WP", ket = "WEB privateServerLinkCode + -S: games/X?privateServerLinkCode=Y",
          cmd = "am start -S -a android.intent.action.VIEW -d '"..webPriv.."' -p "..pkg },
        -- === CARA HIP HUB (dari intip ps-ef panel Hip Hub -- AMAN + selalu masuk) ===
        -- am start -S -a VIEW -d URL -p pkg. Kunci: -S (stop activity lama, start
        -- fresh -> gak no-op ke Home, gak numpuk task). Simpel, tanpa cmp/flag,
        -- Android routing sendiri. URL web share (kayak Pandora).
        { n = "H", ket = "HIP HUB: -S + -p pkg (stop activity, deeplink kita)",
          cmd = "am start -S -a android.intent.action.VIEW -d '"..url.."' -p "..pkg },
        { n = "HN", ket = "HIP HUB + -n cmp: -S + -p + -n ActivityProtocolLaunch",
          cmd = "am start -S -a android.intent.action.VIEW -d '"..url.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch" },
        { n = "P", ket = "PANDORA PERSIS: -p pkg + -n cmp + NEW_TASK (deeplink)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10000000" },
        { n = "PW", ket = "PANDORA + WEB URL (kalau ada share link) -p + -n + NEW_TASK",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10000000" },
        -- === VARIASI CARA PANDORA (cmp ActivityProtocolLaunch, flag beda) ===
        { n = "A1", ket = "Pandora asli: cmp ActivityProtocolLaunch + NEW_TASK (0x10000000)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10000000" },
        { n = "A2", ket = "cmp ActivityProtocolLaunch TANPA flag (biar Android atur)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch" },
        { n = "A3", ket = "cmp ActivityProtocolLaunch + NEW_TASK|MULTIPLE_TASK (0x08000000|0x10000000)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x18000000" },
        { n = "A4", ket = "cmp ActivityProtocolLaunch + NEW_TASK|BROUGHT_TO_FRONT (0x00400000|0x10000000)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10400000" },
        { n = "A5", ket = "cmp ActivityProtocolLaunch + NEW_TASK|RESET_IF_NEEDED (0x00200000|0x10000000)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10200000" },
        -- === PAKAI --user 0 (eksplisit, kadang bantu App Cloner) ===
        { n = "A6", ket = "cmp ActivityProtocolLaunch + NEW_TASK + --user 0",
          cmd = "am start --user 0 -a android.intent.action.VIEW -d '"..url.."' -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10000000" },
        -- === TANPA cmp (biar Android pilih activity, tapi tetep NEW_TASK) ===
        { n = "B1", ket = "am start -p pkg + NEW_TASK (tanpa cmp, Android routing)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -p "..pkg.." -f 0x10000000" },
        { n = "B2", ket = "am start -p pkg polos (cara lama Velium, tanpa flag)",
          cmd = "am start -a android.intent.action.VIEW -d '"..url.."' -p "..pkg },
        -- === MONKEY (launch app biasa, ke Home) ===
        { n = "D1", ket = "monkey launcher (buka app ke Home, gak langsung join)",
          cmd = "monkey -p "..pkg.." -c android.intent.category.LAUNCHER 1" },
    }

    info("=== TES CARA MASUKIN: " .. nama .. " ===")
    -- v7.79: kalau dikasih arg ke-3 (nama cara, mis A3), cuma jalanin ITU aja.
    -- Contoh: velium buka clienu A3  -> tes cara A3 doang (gak semua 9).
    local caraPilih = (arg and arg[3] or ""):upper()
    if caraPilih ~= "" then
        local ketemu = nil
        for _, c in ipairs(cara) do if c.n:upper() == caraPilih then ketemu = c break end end
        if not ketemu then
            err("Cara '" .. caraPilih .. "' gak ada. Pilihan: A1 A2 A3 A4 A5 A6 B1 B2 D1")
            return
        end
        print("")
        print(C.BOLD .. C.Y .. "########## CARA " .. ketemu.n .. " (manual) ##########" .. C.N)
        print(C.C .. "  " .. ketemu.ket .. C.N)
        print(C.D .. "  cmd: " .. ketemu.cmd .. C.N)
        print(C.Y .. "  siap-siap... tembak 5 detik lagi (LIAT LAYAR RF)" .. C.N)
        os.execute("sleep 5")   -- v7.80: delay 5s sebelum aktivasi (user minta)
        sh_silent("su -c \"" .. ketemu.cmd .. "\"")
        print(C.D .. "  << ditembak -- LIAT LAYAR RF: masuk gak? client lain aman? >>" .. C.N)
        return
    end
    -- v7.90: DEFAULT (tanpa argumen cara) = pakai open_one (CARA PANDORA PERSIS
    -- v7.85 -- cara production). Cuma tes 9 cara kalau argumen ke-3 = "tes".
    if caraPilih ~= "TES" then
        info("Buka " .. nama .. " pakai cara Pandora persis (production, open_one)...")
        info("(mau tes 9 cara? ketik: velium buka " .. nama .. " tes)")
        -- v7.93: DEBUG -- tampilin URL + command persis + status client sebelum.
        local urlDbg = build_url(cfg, linkClient)
        local hidup = pkg_hidup(pkg)
        local gNow = grafis_kb(pkg) or 0
        info(("Status: %s, grafis %.0f MB"):format(hidup and "hidup" or "mati", gNow/1024))
        info("URL: " .. urlDbg)
        local cmdDbg = "am start -a android.intent.action.VIEW -d '"..urlDbg.."'"
            .. " -p "..pkg.." -n "..pkg.."/com.roblox.client.ActivityProtocolLaunch -f 0x10000000"
        info("CMD: su -c \"" .. cmdDbg .. "\"")
        -- jalanin + tangkep output (biar keliatan error am start)
        local hasilAm = sh("su -c \"" .. cmdDbg .. " 2>&1\"") or ""
        if hasilAm:match("%S") then info("am start bilang: " .. hasilAm:gsub("%s+"," "):sub(1,120)) end
        info("Ditembak. Cek grafis 30s (masuk gak)...")
        local masuk, mb = cek_masuk_game(pkg, 30, nil)
        if masuk then ok(("%s MASUK GAME (grafis %.0f MB)"):format(nama, mb or 0))
        else warn(("%s belum masuk (grafis %.0f MB)"):format(nama, mb or 0)) end
        info("<< LIAT LAYAR RF: client lain aman? >>")
        return
    end
    info("9 cara (fokus variasi Pandora). Jeda 10s. LIAT: masuk gak? client lain aman?")
    info("am start -S DIBUANG (ngerusak). URL: " .. url)
    info("")
    for _, c in ipairs(cara) do
        print("")
        print(C.BOLD .. C.Y .. "########## CARA " .. c.n .. " ##########" .. C.N)
        print(C.C .. "  " .. c.ket .. C.N)
        print(C.D .. "  cmd: " .. c.cmd .. C.N)
        sh_silent("su -c \"" .. c.cmd .. "\"")
        -- v7.77: jeda 20s bersih (gak ada grafis_kb/jaga_depan yang berat --
        -- dumpsys ~12s bikin total 1 menit). Cukup tembak + tunggu 20s, user
        -- LIAT SENDIRI di layar RF (masuk gak, client lain aman gak).
        print(C.D .. "  << tunggu 10s -- LIAT LAYAR RF sekarang >>" .. C.N)
        os.execute("sleep 10")
    end
    print("")
    info("Semua cara udah dicoba. Cara mana yang MASUK + gak ganggu client lain?")
    return
end

if PERINTAH == "tap" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end

    local target = arg and arg[2] or ""
    local fx = tonumber(arg and arg[3] or "")
    local fy = tonumber(arg and arg[4] or "")
    local kali = math.floor(tonumber(arg and arg[5] or "") or 1)
    -- v4.94: jeda sebelum mencet -- biar sempet liat layarnya pas kepencet
    local jeda = math.floor(tonumber(arg and arg[6] or "") or 0)

    if target == "" or not fx or not fy then
        err("Cara pakai:  velium tap <client> <x> <y> [kali] [jeda-detik]")
        info("   x & y = pecahan 0..1 dari kotak jendela")
        info("   contoh:  velium tap clienu 0.5 0.62 2 5   (pencet 2x, tunggu 5 detik dulu)")
        info("   (0.5 0.5 = tengah jendela; 0.5 0.62 = tengah, agak ke bawah)")
        return
    end
    if fx < 0 or fx > 1 or fy < 0 or fy > 1 then
        err("x & y harus antara 0 dan 1 (itu PECAHAN, bukan piksel).")
        return
    end

    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs)) do
        if p == target or p:find(target, 1, true) then pkg = p break end
    end
    if not pkg then
        err("Client '" .. target .. "' gak ada di config.")
        info("Yang ada: " .. cfg.pkgs)
        return
    end

    print(C.BOLD..C.C.."\n=== TAP KALIBRASI ==="..C.N)
    info("Bawa " .. pkg:gsub("com%.roblox%.","") .. " ke depan (tanpa link join)...")
    local _, caraDepan = bawa_depan(pkg)
    info("   lewat: " .. tostring(caraDepan))
    os.execute("sleep 3")

    if jeda > 0 then
        for sisa = jeda, 1, -1 do
            io.write(("\r   mencet dalam %2d detik... (liatin layarnya)"):format(sisa))
            io.flush()
            os.execute("sleep 1")
        end
        io.write("\r" .. string.rep(" ", 55) .. "\r"); io.flush()
    end

    local hasil, sebab = tap_jendela(cfg, pkg, fx, fy, kali)
    if not hasil then
        err("Gagal: " .. tostring(sebab))
        return
    end
    local k = hasil.kotak
    ok(("Jendela: [%d,%d]-[%d,%d]  (%dx%d)"):format(
        k.L, k.T, k.R, k.B, k.R - k.L, k.B - k.T))
    ok(("Dipencet %dx di (%d, %d)  = pecahan %.2f, %.2f"):format(kali, hasil.x, hasil.y, fx, fy))
    print()
    info("Kepencet tombolnya? Kalau meleset, geser angkanya:")
    info("   kegedean ke bawah -> kecilin y   |  kurang ke bawah -> gedein y")
    info("   contoh:  velium tap " .. target .. " " .. fx .. " " .. (fy - 0.05) .. " " .. kali)
    print()
    info("Kalau PAS: cek papan klip udah keisi link key belum, terus simpen di config:")
    info(('   key_tap="%.2f,%.2f"'):format(fx, fy))
    print()
    return
end

if PERINTAH == "lisensi" or PERINTAH == "license" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu."); return end

    local path  = cfg.delta_license or DELTA_LICENSE
    local batas = tonumber(cfg.key_jam) or 24
    local kead, umur = lisensi_keadaan(cfg)

    print(C.BOLD..C.C.."\n=== LISENSI DELTA ==="..C.N)
    info("Berkas : " .. path)
    info("Batas  : " .. batas .. " jam (atur lewat key_jam di config)")

    local isi = (sh("su -c 'cat " .. path .. " 2>/dev/null'") or ""):gsub("%s+$", "")
    if isi ~= "" then
        -- cuma tampilin sebagian -- ini kunci, gak usah kepampang utuh
        info("Kunci  : " .. isi:sub(1, 12) .. "..." .. isi:sub(-4) .. "  (" .. #isi .. " byte)")
    else
        info("Kunci  : (kosong / gak kebaca)")
    end

    if kead == "ada" then
        ok("Keadaan: MASIH BERLAKU" .. (umur and ("  (umur " .. umur_ringkas(umur) .. ")") or ""))
        if umur then
            local sisa = (batas * 3600) - umur
            if sisa > 0 then info("Sisa   : ~" .. umur_ringkas(sisa) .. " lagi sebelum dianggap basi") end
        end
        info("Worker : jalan normal -- client yang diem tetep diurus kayak biasa")
    elseif kead == "hilang" then
        warn("Keadaan: HILANG -- berkasnya gak ada")
        info("Worker : client yang diem GAK disentuh -- restart gak bikin kunci masuk")
        info("Langkah: velium cari <client>   (worker cari tombolnya sendiri)")
    else
        warn("Keadaan: LEWAT UMUR" .. (umur and ("  (" .. umur_ringkas(umur) .. ")") or ""))
        -- v5.01: ini yang dulu bikin salah paham. Umur lisensi TIDAK bikin client
        -- yang lagi jalan tiba-tiba diminta kunci -- Delta cuma meriksa pas MULAI.
        info("Client yang LAGI JALAN tetep AMAN -- Delta cuma meriksa kunci pas app MULAI.")
        info("Mau 28 jam pun gak apa-apa, selama client-nya gak keluar.")
        info("Yang kena cuma client yang DIBUKA ULANG: dia bakal nyangkut di layar key.")
        info("Worker : tetep ngurus client kayak biasa (rejoin dll)")
        info("Langkah: kalau ada client yang gak mau idup lagi -> velium cari <client>")
    end
    print()
    return
end

-- v7.28: VELIUM LOGCAT -- diagnostik. Tampilin SEMUA disconnect/kick dari logcat
-- Roblox, per client. Buat tau pola: disconnect apa aja yang muncul, kode berapa,
-- dari client mana. Dari sini kita tau harus deteksi apa buat auto-rejoin.
-- Cara: ambil PID tiap client -> filter logcat by PID -> cari baris disconnect/
-- kick/reason. Kode 285=DisconnectClientInitiated (keluar sendiri/backgrounding),
-- 267=kicked (game/experience Kick), 264=dobel login, 277=lost connection, dll.
-- v9.184: PATCH /v1/vip-servers/<id> {newJoinCode:true} -> joinCode (= privateServerLinkCode,
-- UNIVERSE-level -- kepake lintas dunia tanpa getps ulang). User nemu endpoint ini.
-- Balikin joinCode string atau nil. tmp = file cookie, vsid = vipServerId.
function getps_joincode(tmp, vsid)
    -- CSRF token dulu (POST kosong -> header x-csrf-token)
    local ch = io.popen(("curl -s -4 -m 20 -i -X POST -H \"Cookie: $(cat %s)\" "
        .. "\"https://auth.roblox.com/v2/logout\" 2>&1"):format(shq(tmp)))
    local cout = ch and ch:read("*all") or ""
    if ch then ch:close() end
    local csrf = cout:match("[xX]%-[cC][sS][rR][fF]%-[tT][oO][kK][eE][nN]:%s*([%w%+/=]+)")
    if not csrf then return nil, "csrf gak dapet" end
    -- PATCH newJoinCode -> joinCode
    local ph = io.popen(("curl -s -4 -m 20 -X PATCH -H \"Cookie: $(cat %s)\" "
        .. "-H \"X-CSRF-TOKEN: %s\" -H \"Content-Type: application/json\" "
        .. "-d '{\"newJoinCode\":true}' "
        .. "\"https://games.roblox.com/v1/vip-servers/%s\" 2>&1"):format(shq(tmp), csrf, vsid))
    local pout = ph and ph:read("*all") or ""
    if ph then ph:close() end
    return pout:match('"joinCode"%s*:%s*"([%w]+)"'), pout:sub(1, 60)
end

function getps_akun(cfg, cookie)
    if not cookie or cookie == "" then return nil, "cookie kosong" end
    -- v8.72: PS per akun. Coba ambil dari place AKTIF (W2 fall) dulu. Kalau kosong
    -- (akun belum punya PS di W2), fallback ke W1 (world lama, biasanya udah punya
    -- PS). accessCode UNIVERSE-level -> bisa join W2 pakai placeId W2. User insight:
    -- "PS-nya sama, tinggal ganti id place ke world 2".
    local W1 = "97598239454123"    -- v9.191: W1 ASLI (Grow a Garden 2 klasik). 129343810645058 = redirect ke W2
    local W2 = "126987765280963"
    local GARDEN1 = "126884695634066"  -- v9.264: GAG 1 garden
    local MARKET1 = "129954712878723"  -- v9.264: GAG 1 market (TradeWorld)
    local aktif = cfg.place_id or W1
    -- v9.189: cek SEMUA dunia (aktif, W1, W2). Bug user: getps cuma cek dunia AKTIF
    -- -> server yg udah ada di dunia LAIN (mis. W2) gak kedeteksi -> kira "belum punya"
    -- -> bikin server BARU tiap kali. Karena joinCode UNIVERSE-level, server dari dunia
    -- mana pun kepake buat dunia aktif (tinggal ganti placeId). Jadi cek semua, temu = pake.
    -- v9.264: place tambahan TERGANTUNG GAME. accessCode universe-level -> PS dari place
    -- se-universe kepake. GAG 1 (garden+market = 1 universe) BEDA universe dari GAG 2 (W1/W2).
    -- Dulu selalu cek W1/W2 -> buat GAG 1 percuma (universe beda) + bikin PS baru terus.
    local coba = {}
    coba[#coba+1] = aktif
    if (cfg.game_label or ""):upper():find("GAG 1") then
        if aktif ~= GARDEN1 then coba[#coba+1] = GARDEN1 end
        if aktif ~= MARKET1 then coba[#coba+1] = MARKET1 end
    else
        if aktif ~= W1 then coba[#coba+1] = W1 end
        if aktif ~= W2 then coba[#coba+1] = W2 end
    end

    local tmp = (os.getenv("HOME") or ".") .. "/nx_getps.txt"
    os.remove(tmp)
    local hf = io.open(tmp, "w")
    if not hf then return nil, "gak bisa nulis tmp" end
    hf:write(".ROBLOSECURITY=" .. cookie)
    hf:close()

    -- v8.72: coba tiap place (aktif/W2 dulu, W1 fallback). Begitu dapet accessCode
    -- -> pakai. accessCode dari W1 tetep bisa join W2 (universe sama).
    local sebabAkhir = "accessCode gak ketemu"
    for _, place in ipairs(coba) do
        local url = "https://games.roblox.com/v1/games/" .. place .. "/private-servers?cursor="
        local cmd = ("curl -s -4 -m 20 -H \"Cookie: $(cat %s)\" \"%s\" 2>&1"):format(shq(tmp), url)
        local h = io.popen(cmd)
        local out = h and h:read("*all") or ""
        if h then h:close() end
        -- v9.191: FINAL -> accessCode. TERBUKTI (chat lama + debug): privateServerLinkCode/
        -- joinCode CUMA jalan di BROWSER (Roblox terjemahin linkCode->accessCode di
        -- belakang layar). Executor/am start GAK bisa terjemahin -> masuk PUBLIC.
        -- accessCode dipake langsung executor -> join PRIVATE. Ini yg bener dari awal.
        local code = out:match('"accessCode"%s*:%s*"([%w%-]+)"')
        if code then
            local nama = out:match('"name"%s*:%s*"([^"]*)"')
            -- v9.297: ambil SHARE LINK (privateServerLinkCode, buat login PS dari HP).
            -- vipServerId dari LIST -> GET vip-servers/<id> -> field "link". BEDA dari
            -- accessCode: accessCode buat executor tembak, share link buat mobile/browser.
            -- v9.299: kalau "link" KOSONG (share belom di-generate) -> PATCH
            -- {newJoinCode:true} buat GENERATE share link (butuh CSRF). User nemu:
            -- PATCH vip-servers/<id> body {newJoinCode:true} -> balikin "link" fresh.
            local vsid = out:match('"vipServerId"%s*:%s*(%d+)')
            local share = ""
            if vsid then
                local su = "https://games.roblox.com/v1/vip-servers/" .. vsid
                -- 1) GET link yg udah ada
                local sh = io.popen(("curl -s -4 -m 15 -H \"Cookie: $(cat %s)\" \"%s\" 2>&1"):format(shq(tmp), su))
                local so = sh and sh:read("*all") or ""
                if sh then sh:close() end
                share = so:match('"link"%s*:%s*"([^"]+)"') or ""
                -- 2) kosong -> PATCH generate (ambil CSRF dulu)
                if share == "" then
                    local cc = io.popen(("curl -s -4 -m 20 -i -X POST -H \"Cookie: $(cat %s)\" \"https://auth.roblox.com/v2/logout\" 2>&1"):format(shq(tmp)))
                    local co = cc and cc:read("*all") or ""
                    if cc then cc:close() end
                    local csrf = co:match("[xX]%-[cC][sS][rR][fF]%-[tT][oO][kK][eE][nN]:%s*([%w%+/=]+)")
                    if csrf then
                        local pc = io.popen((
                            "curl -s -4 -m 20 -X PATCH "
                            .. "-H \"Cookie: $(cat %s)\" "
                            .. "-H \"X-CSRF-TOKEN: %s\" "
                            .. "-H \"Content-Type: application/json\" "
                            .. "-d '{\"newJoinCode\":true}' \"%s\" 2>&1"
                        ):format(shq(tmp), csrf, su))
                        local po = pc and pc:read("*all") or ""
                        if pc then pc:close() end
                        share = po:match('"link"%s*:%s*"([^"]+)"') or ""
                    end
                end
            end
            os.remove(tmp)
            return code, (nama or "PS") .. " [accessCode PRIVATE]", share
        end
        if out:find('"data"%s*:%s*%[%s*%]') then sebabAkhir = "akun belum punya PS"
        elseif out:lower():find("unauthorized") or out:find('"errors"') then sebabAkhir = "cookie invalid/error" end
    end

    -- v8.85: akun BELUM PUNYA PS -> BIKIN BARU (free private server, GAG gratis).
    -- User: PS GAG gratis, dulu pencet private server auto-kebuat. Cara:
    --   1. placeId -> universeId (apis.roblox.com/universes)
    --   2. POST games.roblox.com/v1/games/vip-servers/{universeId} (butuh CSRF)
    -- accessCode balik dari response -> join pakai placeId aktif (W2).
    if sebabAkhir == "akun belum punya PS" then
        -- v9.264: ambil universeId dari place AKTIF (dulu hardcode W1 = universe GAG 2).
        -- pakai aktif -> GAG 1 dapet universe GAG 1, GAG 2 dapet universe GAG 2.
        local uniUrl = "https://apis.roblox.com/universes/v1/places/" .. aktif .. "/universe"
        local uh = io.popen(("curl -s -4 -m 20 \"%s\" 2>&1"):format(uniUrl))
        local uout = uh and uh:read("*all") or ""
        if uh then uh:close() end
        local universeId = uout:match('"universeId"%s*:%s*(%d+)')
        -- fallback universeId kalau lookup gagal (rate limit / error):
        --   GAG 1 -> 7436755782 (dari API user: POST vip-servers/7436755782 -> accessCode OK)
        --   GAG 2 -> 10200395747
        if not universeId then
            if (cfg.game_label or ""):upper():find("GAG 1") then
                universeId = "7436755782"   -- v9.293: GAG 1 universe (fallback)
            else
                universeId = "10200395747"  -- GAG 2 universe (fallback)
            end
        end
        if universeId then
            -- ambil CSRF token dulu (POST kosong -> header x-csrf-token)
            local csrfCmd = ("curl -s -4 -m 20 -i -X POST -H \"Cookie: $(cat %s)\" "
                .. "\"https://auth.roblox.com/v2/logout\" 2>&1"):format(shq(tmp))
            local ch = io.popen(csrfCmd)
            local cout = ch and ch:read("*all") or ""
            if ch then ch:close() end
            local csrf = cout:match("[xX]%-[cC][sS][rR][fF]%-[tT][oO][kK][eE][nN]:%s*([%w%+/=]+)")
            if csrf then
                -- POST bikin VIP server (free). Body WAJIB: name, expectedPrice:0
                -- (0 = gratis), idempotencyKey (UUID unik). Format dari request asli
                -- yg berhasil 200 OK. Tanpa expectedPrice+idempotencyKey -> ditolak.
                -- idempotencyKey: bikin UUID acak (biar tiap request unik).
                local function uuid()
                    local t = "0123456789abcdef"
                    local s = ""
                    for i = 1, 32 do
                        local r = math.random(1, 16)
                        s = s .. t:sub(r, r)   -- 1 char (bukan range)
                        if i == 8 or i == 12 or i == 16 or i == 20 then s = s .. "-" end
                    end
                    return s
                end
                math.randomseed(os.time())
                local idem = uuid()
                local bikinUrl = "https://games.roblox.com/v1/games/vip-servers/" .. universeId
                local body = string.format('{"name":"velium","expectedPrice":0,"idempotencyKey":"%s"}', idem)
                local bikinCmd = ("curl -s -4 -m 25 -X POST -H \"Cookie: $(cat %s)\" "
                    .. "-H \"X-CSRF-TOKEN: %s\" -H \"Content-Type: application/json\" "
                    .. "-d '%s' \"%s\" 2>&1"):format(shq(tmp), csrf, body, bikinUrl)
                local bh = io.popen(bikinCmd)
                local bout = bh and bh:read("*all") or ""
                if bh then bh:close() end
                -- accessCode dari response
                local kode = bout:match('"accessCode"%s*:%s*"([%w%-]+)"')
                if kode then
                    -- v9.297: share link buat PS baru. vipServerId dari response bikin.
                    local vsid = bout:match('"vipServerId"%s*:%s*(%d+)')
                    local share = ""
                    if vsid then
                        local su = "https://games.roblox.com/v1/vip-servers/" .. vsid
                        local sh = io.popen(("curl -s -4 -m 15 -H \"Cookie: $(cat %s)\" \"%s\" 2>&1"):format(shq(tmp), su))
                        local so = sh and sh:read("*all") or ""
                        if sh then sh:close() end
                        share = so:match('"link"%s*:%s*"([^"]+)"') or ""
                    end
                    os.remove(tmp)
                    return kode, "PS BARU dibikin (gratis)", share
                end
                sebabAkhir = "bikin PS gagal: " .. (bout:match('"message"%s*:%s*"([^"]*)"') or bout:sub(1,80))
            else
                sebabAkhir = "CSRF token gak dapet (bikin PS)"
            end
        else
            sebabAkhir = "universeId gak dapet (bikin PS)"
        end
    end

    os.remove(tmp)
    return nil, sebabAkhir
end

-- v9.174: copy cek_cookie_roblox (aslinya kedefinisi SETELAH handler getps, jadi
-- gak kepake inline). Cek status cookie via API Roblox: alive/captcha/ban/dead.
function cek_ck_getps(cookie)
    if not cookie or cookie == "" then return "dead", "cookie kosong" end
    local tmp = (os.getenv("HOME") or ".") .. "/nx_ckgetps.txt"
    os.remove(tmp)
    local hf = io.open(tmp, "w")
    if not hf then return "error", "gak bisa nulis tmp" end
    hf:write(".ROBLOSECURITY=" .. cookie); hf:close()
    local alat = RIW and RIW.http and RIW.http.pilih() or "curl"
    local cmd
    if alat == "wget" then
        cmd = ("wget -qO- --server-response --timeout=15 --header=\"Cookie: $(cat %s)\" " ..
               "https://users.roblox.com/v1/users/authenticated 2>&1"):format(shq(tmp))
    else
        cmd = ("curl -s -4 -m 15 -w \"\nHTTP:%%{http_code}\" -H \"Cookie: $(cat %s)\" " ..
               "https://users.roblox.com/v1/users/authenticated 2>&1"):format(shq(tmp))
    end
    local h = io.popen(cmd)
    local out = h and h:read("*all") or ""
    if h then h:close() end
    os.remove(tmp)
    local kode = out:match("HTTP:(%d+)") or out:match("HTTP/%d%.?%d?%s+(%d+)")
    if kode == "200" and out:find('"name"') then
        return "alive", out:match('"name"%s*:%s*"([^"]*)"')
    end
    local low = out:lower()
    if low:find("captcha") or low:find("challenge") then return "captcha", nil end
    -- v9.237: ban = kata utuh "banned"/"terminated"/"moderated"/frasa ban, ATAU substring
    -- "ban" (buat jaga-jaga response ban yg format-nya beda). Yg penting ban ASLI ke-catch.
    if low:find("ban") or low:find("terminat") or low:find("moderat")
       or low:find("account has been") or low:find("account status") then
        return "ban", ("kode=%s"):format(kode or "?")
    end
    if kode == "401" then return "dead", nil end
    return "error", ("kode=%s"):format(kode or "?")
end

if PERINTAH == "cekplace" then
    local cfg = load_config()
    if not cfg then err("Config gak ada."); return end
    print(C.BOLD .. C.C .. "\n=== CEK PLACE (id game -> nama dunia) ===\n" .. C.N)
    -- ambil cookie dari client pertama yg jalan
    local pkg = nil
    for _, p in ipairs(split(cfg.pkgs or "")) do
        if pkg_running(p) then pkg = p; break end
    end
    if not pkg then err("Gak ada client jalan (buat baca cookie)."); return end
    local db = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
    local hC = io.popen(("su -c %s 2>/dev/null"):format(shq(
        "/data/data/com.termux/files/usr/bin/sqlite3 " .. db ..
        " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
    local raw = hC and hC:read("*all") or ""
    if hC then hC:close() end
    local cookie = nil
    for baris in (raw .. "\n"):gmatch("(.-)\n") do
        baris = baris:gsub("%s+$", "")
        if baris:find("_|WARNING") and (not cookie or #baris > #cookie) then cookie = baris end
    end
    if not cookie then err("Cookie gak kebaca dari " .. pkg); return end
    local tmp = (os.getenv("HOME") or ".") .. "/nx_cekplace.txt"
    os.remove(tmp)
    local hf = io.open(tmp, "w"); hf:write(".ROBLOSECURITY=" .. cookie); hf:close()
    -- placeId yg dicek: arg kalau dikasih, else default (yg dipake selama ini)
    local ids = {}
    if arg and arg[2] then ids[#ids+1] = arg[2]
    else ids = { "129343810645058", "126987765280963", "97598239454123" } end
    for _, id in ipairs(ids) do
        local url = "https://games.roblox.com/v1/games/multiget-place-details?placeIds=" .. id
        local h = io.popen(("curl -s -4 -m 20 -H \"Cookie: $(cat %s)\" \"%s\" 2>&1"):format(shq(tmp), url))
        local out = h and h:read("*all") or ""
        if h then h:close() end
        local nm = out:match('"name"%s*:%s*"([^"]*)"')
        local uni = out:match('"universeId"%s*:%s*(%d+)')
        info(id .. "  ->  " .. (nm and ('"' .. nm .. '"') or "?")
            .. (uni and ("  (universe " .. uni .. ")") or ""))
        if not nm then info("   respon mentah: " .. out:sub(1, 140)) end
    end
    os.remove(tmp)
    print()
    return
end

if PERINTAH == "getps" then
    -- v7.36: GET PS LINK per akun (kayak Pandora). Loop semua akun tim, fetch
    -- accessCode dari API Roblox private-servers (pake cookie akun), simpen ke
    -- backend (kolom ps_link). Worker nanti masuk pake PS masing-masing akun.
    local cfg = load_config()
    if not cfg then err("Config gak ada."); return end
    print(C.BOLD .. C.C .. "\n=== VELIUM GETPS (ambil PS link per akun) ===\n" .. C.N)

    -- v9.292: OVERRIDE place lewat argumen (mis 'velium getps gag1' -> ambil PS GAG 1
    -- walau game RF ini beda). Argumen: gag1/garden/hact, market, gag2/seed/farm.
    -- "ulang" tetep bisa (di arg[2] atau arg[3]).
    do
        local a2 = (arg and arg[2] or ""):lower()
        local a3 = (arg and arg[3] or ""):lower()
        local pilihan = (a2 ~= "" and a2 ~= "ulang") and a2 or a3
        if pilihan == "gag1" or pilihan == "garden" or pilihan == "hact" then
            cfg.place_id = "126884695634066"; cfg.game_label = "GAG 1"
            ok("getps override -> GAG 1 garden (126884695634066)")
        elseif pilihan == "market" then
            cfg.place_id = "129954712878723"; cfg.game_label = "GAG 1 MARKET"
            ok("getps override -> GAG 1 MARKET (129954712878723)")
        elseif pilihan == "gag2" or pilihan == "seed" or pilihan == "farm" then
            cfg.place_id = "129343810645058"; cfg.game_label = "GAG 2"
            ok("getps override -> GAG 2 (129343810645058)")
        end
    end

    -- v8.84 FIX: ambil akun TIM DEVICE INI aja (dari client cfg.pkgs), BUKAN
    -- semua akun fleet (/cookie-list = 285 akun seluruh fleet -> boros + query
    -- akun yg bukan punya device ini). Baca username tiap client di device ini.
    local akunList = {}
    local seen = {}
    local akunPkg = {}   -- v9.174: akun -> client, buat baca cookie kalau backend kosong
    for _, pkg in ipairs(split(cfg.pkgs or "")) do
        local u = baca_username(pkg)
        if u and u ~= "" and u ~= "?" and not seen[u] then
            seen[u] = true
            akunList[#akunList+1] = u
            akunPkg[u] = pkg
        end
    end
    if #akunList == 0 then
        warn("Gak ada akun kebaca di client device ini (prefs username kosong?).")
        return
    end
    -- v9.129: SKIP akun yg UDAH punya PS (server). Baca /ps-list dulu -> buang akun
    -- yg ps_link-nya udah ada. Cuma getps akun yg BELUM punya server (hemat waktu +
    -- gak rate-limit Roblox buat yg gak perlu). Pakai 'velium getps ulang' buat paksa semua.
    if (arg and arg[2] or ""):lower() ~= "ulang" and (arg and arg[3] or ""):lower() ~= "ulang" then
        local punyaPs = {}
        local rList = api_get(cfg, "/ps-list") or ""
        for obj in rList:gmatch('{.-}') do
            local ak = obj:match('"akun"%s*:%s*"(.-)"')
            local psl = obj:match('"ps_link"%s*:%s*"(.-)"')
            if ak and psl and psl ~= "" then punyaPs[ak] = true end
        end
        local sisa = {}
        local nSkip = 0
        for _, ak in ipairs(akunList) do
            if punyaPs[ak] then nSkip = nSkip + 1
            else sisa[#sisa+1] = ak end
        end
        if nSkip > 0 then
            info(("%d akun udah punya server -> SKIP (getps cuma yg belum)."):format(nSkip))
        end
        akunList = sisa
        if #akunList == 0 then
            ok("Semua akun udah punya server. Gak ada yg perlu getps. (pakai 'velium getps ulang' buat paksa semua)")
            return
        end
    end
    info(("%d akun BELUM punya server -- ambil PS link satu-satu..."):format(#akunList))
    print()

    local dapet, gagal = 0, 0
    for _, akun in ipairs(akunList) do
        -- ambil cookie akun
        local ck = api_get(cfg, "/cookie-satu?akun=" .. akun) or ""
        local cookie = ck:match('"cookie"%s*:%s*"([^"]+)"')
        if not cookie or cookie == "" then
            -- v9.174: cookie KOSONG di backend -> LOGIN: baca cookie dari CLIENT yg
            -- login akun ini + cek status. Hidup -> simpen + lanjut getps.
            -- Captcha/ban/mati -> LAPOR ke panel (/cookie-status) + skip.
            local pkgA = akunPkg[akun]
            local ckClient = nil
            if pkgA then
                local db = "/data/data/" .. pkgA .. "/app_webview/Default/Cookies"
                local hC = io.popen(("su -c %s 2>/dev/null"):format(shq(
                    "/data/data/com.termux/files/usr/bin/sqlite3 " .. db ..
                    " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
                local raw = hC and hC:read("*all") or ""
                if hC then hC:close() end
                for baris in (raw .. "\n"):gmatch("(.-)\n") do
                    baris = baris:gsub("%s+$", "")
                    if baris:find("_|WARNING") and (not ckClient or #baris > #ckClient) then ckClient = baris end
                end
            end
            if not ckClient then
                warn(("%s: cookie kosong + client gak login akun ini -> skip"):format(akun))
                gagal = gagal + 1
            else
                info(("%s: cookie kosong -> LOGIN (cek status dari client)..."):format(akun))
                local keadaan, ketCk = cek_ck_getps(ckClient)
                if keadaan == "alive" then
                    cookie = ckClient
                    pcall(function() api_post(cfg, "/cookie-simpan",
                        string.format('{"akun":%s,"paket":%s,"cookie":%s}', jstr(akun), jstr(pkgA), jstr(cookie))) end)
                    ok(("%s: cookie HIDUP -> disimpen + lanjut getps"):format(akun))
                elseif keadaan == "captcha" or keadaan == "ban" or keadaan == "dead" then
                    pcall(function() api_post(cfg, "/cookie-status",
                        string.format('{"akun":%s,"status":%s}', jstr(akun), jstr(keadaan))) end)
                    warn(("%s: cookie %s -> LAPOR ke panel + skip"):format(akun, keadaan))
                    gagal = gagal + 1
                else
                    warn(("%s: cek cookie gagal (%s) -> skip"):format(akun, ketCk or "?"))
                    gagal = gagal + 1
                end
            end
        end
        if cookie and cookie ~= "" then
            local code, ket, share = getps_akun(cfg, cookie)
            if code then
                -- v9.191: accessCode (join PRIVATE via executor). prefix "accessCode=".
                local psLink = (code:sub(1,4) == "http") and code or ("accessCode=" .. code)
                -- v9.297: pack SHARE LINK (buat login PS dari HP) di belakang, dipisah "|share=".
                -- Worker split pas join (pakai accessCode), panel split pas Salin PS (pakai share).
                if share and share ~= "" then psLink = psLink .. "|share=" .. share end
                local simpanOk, resp = false, ""
                pcall(function()
                    resp = api_post(cfg, "/ps-simpan",
                        string.format('{"akun":%s,"ps_link":%s}', jstr(akun), jstr(psLink)), "POST") or ""
                    -- v9.73: cek respon simpan. backend return {"ok":true} kalau
                    -- sukses. kalau kolom ps_link belum ada -> {"ok":false}.
                    simpanOk = resp:find('"ok"%s*:%s*true') ~= nil
                end)
                if simpanOk then
                    ok(("%s -> PS dapet + kesimpen (%s)"):format(akun, ket or "PS"))
                    dapet = dapet + 1
                else
                    -- v9.73: PS dapet dari Roblox TAPI GAGAL simpan ke backend.
                    -- Ini sebab "10 dapet PS tapi ps-list 0 -> public". Log jelas.
                    warn(("%s -> PS dapet TAPI GAGAL SIMPAN: %s"):format(
                        akun, resp ~= "" and resp:sub(1, 80) or "respon kosong"))
                    gagal = gagal + 1
                end
            else
                warn(("%s -> gagal: %s"):format(akun, ket or "?"))
                gagal = gagal + 1
            end
        end
        os.execute("sleep 1")   -- jeda biar gak kena rate-limit Roblox
    end
    print()
    ok(("Selesai: %d dapet PS, %d gagal."):format(dapet, gagal))
    info("Worker bakal masuk PS masing-masing akun (kalau ps_link kesimpen).")
    return
end

if PERINTAH == "rejoin-log" then
    -- v7.32: liat log rejoin (siapa + dari baris mana + berapa sering).
    local sub = arg and arg[2] or ""
    local RJ = "/sdcard/velium_rejoin.log"
    if sub == "clear" or sub == "hapus" then
        os.execute("rm -f " .. RJ)
        ok("Log rejoin dihapus.")
        return
    end
    print(C.BOLD .. C.C .. "\n=== VELIUM REJOIN-LOG ===\n" .. C.N)
    local f = io.open(RJ, "r")
    if not f then warn("Belum ada log rejoin (worker belum rejoin apa-apa)."); return end
    local isi = f:read("*all") or ""; f:close()
    if isi == "" then warn("Log rejoin kosong."); return end
    local baris = {}
    for l in isi:gmatch("[^\n]+") do baris[#baris+1] = l end

    -- ringkasan: per ALASAN (jalur) -- yang paling sering = biang rejoin
    local perBaris, perClient = {}, {}
    for _, l in ipairs(baris) do
        -- format: "HH:MM:SS | client | alasan"
        local cl = l:match("| (%S+) | ") or "?"
        local al = l:match("| %S+ | (.+)$") or "?"
        perBaris[al] = (perBaris[al] or 0) + 1
        perClient[cl] = (perClient[cl] or 0) + 1
    end
    info(("Total %d rejoin terekam:"):format(#baris))
    print()
    info("Per ALASAN -- yang paling sering = biang rejoin:")
    -- urut dari terbanyak
    local arrB = {}
    for br, n in pairs(perBaris) do arrB[#arrB+1] = {br, n} end
    table.sort(arrB, function(a,b) return a[2] > b[2] end)
    for _, e in ipairs(arrB) do print(("   %-22s x%d"):format(e[1], e[2])) end
    print()
    info("Per CLIENT:")
    local arrC = {}
    for cl, n in pairs(perClient) do arrC[#arrC+1] = {cl, n} end
    table.sort(arrC, function(a,b) return a[2] > b[2] end)
    for _, e in ipairs(arrC) do print(("   %-10s x%d"):format(e[1], e[2])) end
    print()
    info("Detail (30 terakhir):")
    local mulai = math.max(1, #baris - 29)
    for i = mulai, #baris do print("   " .. baris[i]) end
    print()
    info("Tempel ini ke chat -- biar tau baris mana yang bikin rejoin bareng.")
    info("Hapus: velium rejoin-log clear")
    return
end

if PERINTAH == "denyut" then
    -- cek kapan TERAKHIR denyut tiap akun (isi timestamp + mtime file).
    -- buat lihat: file di-update terus (script jalan) atau udah lama (mati).
    print(C.BOLD .. C.C .. "\n=== VELIUM DENYUT (kapan terakhir tiap akun) ===\n" .. C.N)
    local sekarang = os.time()
    local jamNow = os.date("%H:%M:%S")
    info("Jam device sekarang: " .. jamNow .. "  (epoch " .. sekarang .. ")")
    print()
    -- baca semua file denyut: nama|isi|mtime
    local raw = ""
    local ph = io.popen("su -c 'for f in /sdcard/Delta/Workspace/velium_denyut_*.txt \"/sdcard/Arceus X/Workspace/\"velium_denyut_*.txt; do [ -f \"$f\" ] && echo \"$(basename $f)|$(cat $f 2>/dev/null)|$(stat -c %Y \"$f\" 2>/dev/null)\"; done' 2>/dev/null")
    if ph then raw = ph:read("*all") or ""; ph:close() end
    if raw == "" then
        warn("Gak ada file denyut (script belum nulis / path beda).")
        info("Path dicek: /sdcard/Delta/Workspace/ + /sdcard/Arceus X/Workspace/ velium_denyut_*.txt")
        return
    end
    local ada = 0
    for line in raw:gmatch("[^\n]+") do
        local nama, ts, mtime = line:match("velium_denyut_(.-)%.txt|(%d+)|(%d+)")
        if nama and ts then
            ada = ada + 1
            local umurIsi = sekarang - tonumber(ts)
            local umurMtime = mtime and (sekarang - tonumber(mtime)) or nil
            -- format umur jadi "Xm Ys"
            local function fmt(d)
                if not d then return "?" end
                if d < 0 then d = 0 end
                local m = math.floor(d/60); local s = d % 60
                return m > 0 and ("%dm %ds"):format(m, s) or ("%ds"):format(s)
            end
            local jamIsi = os.date("%H:%M:%S", tonumber(ts))
            local status = umurIsi <= 180 and (C.G .. "FRESH" .. C.N) or (C.R .. "MATI" .. C.N)
            print(("  %-16s isi=%s (jam %s) | mtime=%s | %s"):format(
                nama, fmt(umurIsi), jamIsi, fmt(umurMtime), status))
        end
    end
    print()
    if ada == 0 then warn("File ada tapi format isi gak kebaca (bukan angka?).") end
    info("isi = umur dari timestamp DALAM file (yg script tulis)")
    info("mtime = umur dari kapan file terakhir DIUBAH (metadata OS)")
    info("FRESH = <2 menit (script jalan) | MATI = >2 menit (disconnect)")
    return
end

if PERINTAH == "logcat" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu buat setup."); return end
    print(C.BOLD .. C.C .. "\n=== VELIUM LOGCAT (history disconnect) ===\n" .. C.N)

    -- v7.29: baca dari FILE history yang direkam worker (/sdcard/velium_disconnect.log).
    -- Worker ngerekam disconnect tiap 30s sambil jalan. `velium logcat clear` = hapus.
    local sub = arg and arg[2] or ""
    if sub == "clear" or sub == "hapus" then
        os.execute("rm -f " .. DC_LOG)
        ok("History disconnect dihapus (" .. DC_LOG .. ")")
        return
    end

    local f = io.open(DC_LOG, "r")
    if not f then
        warn("Belum ada history disconnect.")
        info("Worker ngerekam otomatis tiap 30s sambil jalan (FORCE).")
        info("Kalau worker baru nyala / belum ada disconnect, file belum kebikin.")
        info("Biarin worker jalan, disconnect bakal kerekam sendiri.")
        return
    end
    local isi = f:read("*all") or ""
    f:close()
    if isi == "" then warn("History kosong."); return end

    -- kumpulin baris + ringkasan per kode
    local baris = {}
    for l in isi:gmatch("[^\n]+") do baris[#baris+1] = l end
    local ringkas = {}
    for _, l in ipairs(baris) do
        local k = l:match("kode=(%S+)") or "-"
        ringkas[k] = (ringkas[k] or 0) + 1
    end

    info(("Total %d disconnect terekam:"):format(#baris))
    print()
    info("Ringkasan per kode:")
    for k, n in pairs(ringkas) do
        local ket = (k == "285") and "keluar sendiri / backgrounding (NORMAL)"
                 or (k == "267") and "KICKED game/experience (perlu rejoin!)"
                 or (k == "264") and "dobel login (akun kepakai di tempat lain)"
                 or (k == "277") and "lost connection"
                 or (k == "268") and "untrusted / ditolak"
                 or (k == "-") and "tanpa kode (save data / remove / kicked teks)"
                 or "?"
        print(("   kode %-6s x%-4d %s"):format(k, n, ket))
    end
    print()

    -- 30 baris terakhir (paling baru)
    info("Detail (30 terakhir):")
    local mulai = math.max(1, #baris - 29)
    for i = mulai, #baris do
        local l = baris[i]
        local kode = l:match("kode=(%S+)")
        local warna = (kode == "267") and C.R or (kode == "285") and C.Y or C.N
        print(warna .. "   " .. l:sub(1, 130) .. C.N)
    end
    print()
    info("267/save data = kick (rejoin). 285 = keluar sendiri (normal).")
    info("Hapus history:  velium logcat clear")
    info("Tempel hasil ini ke chat biar tau pola disconnect-nya.")
    return
end

if PERINTAH == "logcat-live" then
    local cfg = load_config()
    if not cfg then err("Config belum ada."); return end
    local daftar = split(cfg.pkgs)
    print(C.BOLD .. C.C .. "\n=== VELIUM LOGCAT LIVE (dump sekarang) ===\n" .. C.N)

    -- ambil PID tiap client (biar tau baris log dari client mana)
    local pidKe = {}   -- pid -> nama client
    for _, pkg in ipairs(daftar) do
        local nama = pkg:gsub("com%.roblox%.", "")
        local h = io.popen("su -c 'pidof " .. pkg .. "' 2>/dev/null")
        local pids = h and h:read("*all") or ""
        if h then h:close() end
        for pid in pids:gmatch("%d+") do pidKe[pid] = nama end
    end
    local adaPid = false
    for _ in pairs(pidKe) do adaPid = true break end
    if not adaPid then
        warn("Gak ada client jalan (gak ada PID). Start dulu, baru cek logcat.")
        return
    end
    info("Client jalan:")
    do
        local seen = {}
        for pid, nama in pairs(pidKe) do
            if not seen[nama] then print("   " .. nama .. " (pid " .. pid .. ")"); seen[nama]=true end
        end
    end
    print()

    -- ambil logcat penuh (dump), cari baris disconnect/kick/reason
    info("Baca logcat (dump)...")
    local h = io.popen("su -c 'logcat -d' 2>/dev/null")
    local semua = h and h:read("*all") or ""
    if h then h:close() end
    if semua == "" then warn("Logcat kosong / gak kebaca."); return end

    -- filter: baris yang ada Roblox + (disconnect/kick/reason/removed/save data)
    local hits = {}
    for baris in semua:gmatch("[^\n]+") do
        local low = baris:lower()
        if (low:find("roblox") or low:find("networkclient") or low:find("rbxtransport"))
           and (low:find("disconnect") or low:find("kick") or low:find("reason:")
                or low:find("networkclient:remove") or low:find("save data")
                or low:find("error code") or low:find("teleport")) then
            -- ambil PID dari kolom ke-2 (format: date time PID TID ...)
            local pid = baris:match("^%S+%s+%S+%s+(%d+)")
            local nama = pid and pidKe[pid] or "?"
            -- ambil kode reason kalau ada: "reason: Player: NNN (Xxx)"
            local kode = baris:match("reason:%s*%a*:?%s*(%d+)")
            local jenis = baris:match("%((%w+)%)")   -- (DisconnectClientInitiated)
            hits[#hits+1] = { nama = nama, kode = kode, jenis = jenis, teks = baris }
        end
    end

    if #hits == 0 then
        warn("Gak nemu baris disconnect/kick di logcat.")
        info("Mungkin: (1) belum ada yang disconnect, (2) log udah ke-rotate/ketimpa.")
        info("Coba lagi PAS ada client kena kick/keluar.")
        return
    end

    print(C.BOLD .. ("Nemu %d baris disconnect/kick:"):format(#hits) .. C.N .. "\n")
    -- ringkasan per kode
    local ringkas = {}
    for _, hit in ipairs(hits) do
        local k = hit.kode or (hit.jenis or "?")
        ringkas[k] = (ringkas[k] or 0) + 1
    end
    info("Ringkasan kode disconnect:")
    for k, n in pairs(ringkas) do
        local ket = (k == "285") and "keluar sendiri / backgrounding (NORMAL)"
                 or (k == "267") and "KICKED (game/experience -- ini yang rejoin!)"
                 or (k == "264") and "dobel login (akun kepakai di tempat lain)"
                 or (k == "277") and "lost connection"
                 or (k == "268") and "untrusted / ditolak"
                 or "?"
        print(("   kode %-6s x%-3d  %s"):format(k, n, ket))
    end
    print()

    -- detail 20 baris terakhir (paling baru)
    info("Detail (20 terakhir):")
    local mulai = math.max(1, #hits - 19)
    for i = mulai, #hits do
        local hit = hits[i]
        local tag = hit.kode and ("kode " .. hit.kode) or (hit.jenis or "?")
        -- warna: 267/kick = merah (perlu rejoin), 285 = kuning (normal)
        local warna = (hit.kode == "267") and C.R
                   or (hit.kode == "285") and C.Y
                   or C.N
        -- ambil bagian inti baris (buang timestamp panjang)
        local inti = hit.teks:match("%[.*%]?.*$") or hit.teks
        inti = inti:sub(1, 120)
        print(warna .. ("   [%s] %s"):format(hit.nama, inti) .. C.N)
    end
    print()
    info("Kode 267 = kena KICK (rejoin). Kode 285 = keluar sendiri (normal, gak usah rejoin).")
    info("Tempel hasil ini ke chat biar tau pola disconnect-nya.")
    return
end

if PERINTAH == "intip" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu buat setup."); return end

    local daftar = split(cfg.pkgs)
    local pilih  = arg and arg[2] or ""
    local jeda   = tonumber(arg and arg[3] or "") or 5

    if pilih == "" then
        print(C.BOLD..C.C.."\n=== INTIP LAYAR CLIENT ===\n"..C.N)
        info("Client di tim ini:")
        for _, p in ipairs(daftar) do
            print("   " .. p:gsub("com%.roblox%.", "") ..
                  (pkg_running(p) and (C.G.."  [jalan]"..C.N) or (C.Y.."  [off]"..C.N)))
        end
        print()
        info("Contoh:  velium intip clienu 20")
        info("         (nunggu 20 detik, baru dipotret -- sempet pindah layar dulu)")
        return
    end

    -- boleh ketik pendek (clienu) atau lengkap (com.roblox.clienu)
    local pkg = nil
    for _, p in ipairs(daftar) do
        if p == pilih or p:gsub("com%.roblox%.", "") == pilih then pkg = p break end
    end
    if not pkg then
        err("Client '" .. pilih .. "' gak ada di config.")
        info("Liat daftarnya:  velium intip")
        return
    end

    print(C.BOLD..C.C.."\n=== INTIP: " .. pkg:gsub("com%.roblox%.", "") .. " ===\n"..C.N)
    if jeda > 0 then
        info("Nunggu " .. jeda .. " detik -- siapin layarnya sekarang.")
        for sisa = jeda, 1, -1 do
            io.write(C.D .. "   " .. sisa .. "...   \r" .. C.N); io.flush()
            os.execute("sleep 1")
        end
        print()
    end

    info("Motret layar...")
    -- lewatiFokus=true: pas diagnosa, mending dapet dump apa adanya daripada
    -- nolak diem-diem cuma gara-gara pengecekan fokus meleset.
    local isi, sebab = ambil_dump(cfg, pkg, nil, true)
    if not isi then err("Gagal: " .. tostring(sebab)); return end

    -- teks unik, urut -- ini yang dipakai buat nyusun penanda
    local liat, unik = {}, {}
    for t in isi:gmatch('text="([^"]+)"') do
        if t:match("%S") and not liat[t] then liat[t] = true; unik[#unik+1] = t end
    end
    table.sort(unik)

    print()
    ok("Teks di layar (" .. #unik .. " potong):")
    if #unik == 0 then
        print(C.D .. "   (kosong -- gak ada satu pun node teks)" .. C.N)
        print(C.D .. "   Ini NORMAL di RedFinger: Roblox nggambar semuanya ke" .. C.N)
        print(C.D .. "   permukaan GL, uiautomator cuma liat cangkangnya. Jadi" .. C.N)
        print(C.D .. "   layar game / key / Home kebacanya SAMA-SAMA kosong --" .. C.N)
        print(C.D .. "   penanda berbasis teks emang gak bisa dipakai di sini." .. C.N)
    end
    for _, t in ipairs(unik) do print("   " .. t) end

    -- penilaian yang PERSIS sama kayak yang dipakai worker
    local pesan, sifat = klasifikasi_layar(isi)
    print()
    ok("Kata worker: " .. (pesan or "gak dikenali (dibiarin)"))
    local tindakan = ({
        manual = "CUMA DICATET -- client gak disentuh",
        tunggu = "ditutup, didiemin dulu",
        home   = "didorong 2x, baru dibunuh kalau bandel",
        ulang  = "dibunuh + dibuka lagi (jatah 3x/30 menit)",
    })[sifat or ""] or "gak ngapa-ngapain"
    ok("Tindakannya: " .. tindakan)
    print()
    info("Kalau penilaiannya SALAH, kirim daftar teks di atas ke Claude.")
    info("Atau tambah sendiri:  key_tanda=\"Kata A,Kata B\"  di config")
    print()
    return
end


if PERINTAH == "key" then
    local a2 = arg and arg[2] or ""

    -- v4.81: `key set` DIDULUIN, sebelum config divalidasi. Kalau config-nya
    -- rusak gara-gara baris kunci, ini yang bisa benerin -- percuma dihadang
    -- duluan. Aman: config_set_bypass nolak nulis kalau hasilnya gak sah.
    if a2:lower() == "set" then
        local apikey = arg and arg[3] or ""
        if apikey == "" then
            err("Kuncinya mana? Contoh:")
            err("   velium key set <kunci-api-bypass.vip>")
            return
        end
        local sukses, sebab = config_set_bypass(apikey)
        if sukses then
            ok("Kunci API kesimpen di " .. CONFIG_FILE)
            info("Cek: velium key <link>")
        else
            err("Gagal: " .. tostring(sebab))
        end
        return
    end

    local cfg = load_config()
    if not cfg then
        -- v4.81: bedain "belum pernah setup" vs "ada tapi rusak". Dulu dua-duanya
        -- dibilang "belum ada" -- bikin salah langkah (setup ulang padahal cuma
        -- perlu benerin satu baris).
        local adaFile = io.open(CONFIG_FILE, "r")
        if adaFile then
            adaFile:close()
            err("Config ADA tapi RUSAK: " .. CONFIG_FILE)
            local bak = io.open(CONFIG_FILE .. ".bak", "r")
            if bak then
                bak:close()
                info("Ada cadangannya. Balikin pakai:")
                info("   cp " .. CONFIG_FILE .. ".bak " .. CONFIG_FILE)
            else
                info("Liat isinya:  cat " .. CONFIG_FILE)
                info("Atau setup ulang:  rm " .. CONFIG_FILE .. " && velium")
            end
        else
            err("Config belum ada. Jalanin `velium` dulu buat setup.")
        end
        return
    end

    local pakaiRefresh = (a2:lower() == "refresh")
    local link = pakaiRefresh and (arg and arg[3] or "") or a2

    if link == "" then
        link = clipboard_ambil()
        if link then
            info("Link diambil dari clipboard")
        else
            err("Gak ada link. Salin dulu link key-nya, atau ketik:")
            err("   lua5.4 velium_worker.lua key <link>")
            info("(clipboard butuh paket termux-api: pkg install termux-api)")
            return
        end
    end

    print(C.BOLD..C.C.."\n=== BYPASS KEY DELTA ==="..C.N)
    do  -- v4.86: kabarin keadaan lisensi sekarang, biar keliatan perlu apa nggak
        local kead, umur = lisensi_keadaan(cfg)
        local warna = (kead == "ada") and C.G or C.Y
        info("Lisensi sekarang: " .. warna .. kead .. C.N ..
             (umur and ("  (umur " .. umur_ringkas(umur) .. ")") or ""))
    end
    info("Link  : " .. link:sub(1, 60) .. (#link > 60 and "..." or ""))
    info("Mode  : " .. (pakaiRefresh and "refresh (proses ulang)" or "biasa"))
    info("Proses... (bisa 30-60 detik, jangan ditutup)")

    local kunci, sebab, mentah = bypass_kunci(cfg, link, pakaiRefresh)
    print()
    if kunci then
        ok("KUNCI: " .. kunci)
        -- disimpen juga, biar gak ilang kalau layar Termux ke-clear
        local f = io.open((os.getenv("HOME") or ".") .. "/velium_key.txt", "w")
        if f then
            f:write(kunci .. "\n"); f:close()
            info("Disimpen di ~/velium_key.txt")
        end
        -- taro ke clipboard kalau termux-api ada -- tinggal tempel di Delta
        os.execute("printf %s " .. shq(kunci) .. " | timeout 10 termux-clipboard-set >/dev/null 2>&1")
        -- v4.80: langsung tulis ke file lisensi Delta -- gak usah tempel manual.
        local wok, wket = tulis_lisensi(cfg, kunci)
        if wok then
            ok("Ditulis ke Delta: " .. wket)
            info("Semua client kepakai (file ini dipakai bareng). Buka ulang Delta.")
        else
            warn("Gagal nulis ke Delta: " .. tostring(wket))
            warn("Kuncinya udah di clipboard -- tempel manual aja dulu.")
        end
    else
        err("GAGAL: " .. tostring(sebab))
        if mentah and mentah:gsub("%s+", "") ~= "" then
            print()
            info("Jawaban mentah dari API (kirim ini ke Claude kalau bentuknya beda):")
            print(C.D .. mentah:sub(1, 900) .. C.N)
        end
    end
    print()
    return
end

if PERINTAH == "status" then
    local pid = baca_pid()
    if pid_hidup(pid) then
        ok("Jalan (pid " .. pid .. ")")
        print(sh("ps -p " .. pid .. " -o pid,etime,cmd="))
    else
        warn("Gak jalan.")
        if pid then info("PID file basi (" .. pid .. ") -> dihapus"); hapus(PID_FILE) end
    end
    return
end

-- v4.34: `lua velium_worker.lua cek` -> tunjukin APA yang worker liat per client.
-- Buat nyari tau kenapa client kebaca "off" padahal game-nya jalan.
if PERINTAH == "cek" and arg and arg[2] == "clien" then
    -- v9.160: "velium cek clien" -> daftar NO MERCY <-> client <-> akun + status.
    -- Nomor no mercy = urutan client (pindai_pkgs, natural sort). Batch su:
    -- 1x buat running (pkg_running_semua) + 1x buat username semua client.
    print(C.BOLD..C.C.."\n=== VELIUM CEK CLIEN (no mercy <-> akun) ===\n"..C.N)
    local pkgs = pindai_pkgs()
    if #pkgs == 0 then warn("Gak ada client Roblox kepasang."); return end
    local hasil, hidup = pkg_running_semua(pkgs)
    -- batch baca username semua client (1 su call, biar gak 20x ~6s)
    local bagian = {}
    for _, p in ipairs(pkgs) do
        bagian[#bagian+1] = 'echo "@U ' .. p .. '"; cat /data/data/' .. p .. '/shared_prefs/prefs.xml 2>/dev/null'
    end
    local out = sh_tmo("su -c '" .. table.concat(bagian, "; ") .. "'", #pkgs + 15) or ""
    local akunMap, curPkg = {}, nil
    for baris in out:gmatch("[^\r\n]+") do
        local up = baris:match("^@U%s+(%S+)")
        if up then curPkg = up
        elseif curPkg then
            local u = baris:match('<string name="username">(.-)</string>')
            if u then akunMap[curPkg] = u end
        end
    end
    for i, pkg in ipairs(pkgs) do
        local akun = akunMap[pkg] or "?"
        local st
        if hasil[pkg] then st = C.G.."[JALAN]"..C.N
        elseif hidup[pkg] then st = C.Y.."[latar]"..C.N
        else st = C.D.."[off]"..C.N end
        print(("%sno mercy %-2d%s -> %s%-14s%s  akun: %s%-14s%s  %s"):format(
            C.BOLD, i, C.N,
            C.D, pkg:gsub("com%.roblox%.", ""), C.N,
            C.C, akun, C.N, st))
    end
    print("")
    return
end

if PERINTAH == "cek" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin setup dulu."); return end
    print(C.BOLD..C.C.."\n=== DIAGNOSA DETEKSI CLIENT ===\n"..C.N)
    for _, pkg in ipairs(split(cfg.pkgs)) do
        print(C.BOLD..pkg..C.N)
        local pid = sh("su -c 'pidof " .. pkg .. "'") or ""
        print("  proses idup : " .. (pid:match("%d") and (C.G.."YA ("..pid:gsub("%s+$","")..")"..C.N) or (C.Y.."NGGAK"..C.N)))
        local o = sh("su -c 'dumpsys activity activities | grep ActivityRecord | grep " .. pkg .. "'") or ""
        if o:match("%S") then
            print("  baris ActivityRecord:")
            for line in o:gmatch("[^\n]+") do
                print("    " .. C.D .. line:gsub("^%s+",""):sub(1,150) .. C.N)
            end
        else
            print("  " .. C.Y .. "gak ada baris ActivityRecord sama sekali" .. C.N)
        end
        print("  dibaca worker: " .. (pkg_running(pkg) and (C.G.."JALAN"..C.N) or (C.Y.."OFF"..C.N)))
        print("")
    end
    print(C.D.."Kalau 'proses idup: YA' tapi 'dibaca worker: OFF', kirim baris"..C.N)
    print(C.D.."ActivityRecord di atas -- dari situ ketauan penanda yang bener."..C.N)
    return
end

if PERINTAH == "hapus" then
    -- v7.07: UNINSTALL SEMUA client Roblox dari RF. Pindai paket roblox, hapus
    -- satu-satu. Konfirmasi dulu (biar gak kehapus gak sengaja).
    print(C.BOLD .. C.C .. ">>> VELIUM HAPUS -- uninstall semua client <<<" .. C.N)
    local pkgs = pindai_pkgs()
    if #pkgs == 0 then
        warn("Gak ada client Roblox kepasang.")
        return
    end
    info("Client kepasang (" .. #pkgs .. "):")
    for _, pk in ipairs(pkgs) do info("  - " .. pk) end
    io.write("Yakin HAPUS semua " .. #pkgs .. " client? (ketik 'ya' buat lanjut): ")
    io.flush()
    local jwb = io.read("*l") or ""
    if jwb:lower() ~= "ya" then
        warn("Dibatalin.")
        return
    end
    -- stop worker dulu (biar gak ganggu)
    sh_silent("pkill -f 'lua.*velium_worker.lua' 2>/dev/null")
    os.execute("sleep 1")
    local ok_n, gagal_n = 0, 0
    for _, pk in ipairs(pkgs) do
        info("Uninstall " .. pk .. "...")
        -- force-stop dulu, terus uninstall (su, timeout biar gak hang)
        sh_silent("am force-stop " .. pk)
        local hasil = sh(("timeout 60 su -c 'pm uninstall %s' 2>&1"):format(pk))
        if hasil:find("Success") then
            ok(pk .. " kehapus.")
            ok_n = ok_n + 1
        else
            -- coba tanpa su (kalau pm uninstall butuh user)
            local h2 = sh(("timeout 60 pm uninstall %s 2>&1"):format(pk))
            if h2:find("Success") then
                ok(pk .. " kehapus.")
                ok_n = ok_n + 1
            else
                warn(pk .. " GAGAL: " .. (hasil:sub(1,60)))
                gagal_n = gagal_n + 1
            end
        end
    end
    print("")
    ok(("SELESAI: %d client kehapus%s"):format(
        ok_n, gagal_n > 0 and (", " .. gagal_n .. " gagal") or ""))
    return
end

if PERINTAH == "stop" then
    local pid = baca_pid()
    if not pid_hidup(pid) then
        warn("Gak ada yang jalan.")
        hapus(PID_FILE); hapus(STOP_FILE)
        -- jaga-jaga ada yatim piatu dari sesi lama
        local yatim = sh("pgrep -f velium_worker.lua")
        if #yatim > 1 then
            warn("Tapi ada proses nyangkut. Dibunuh...")
            sh_silent("pkill -f 'lua.*velium_worker.lua'")
        end
        sh_silent("termux-notification-remove velium_worker")
        sh_silent("termux-wake-unlock")
        return
    end

    -- v5.14: perintah panjang (cari/ukur/pantau) itu proses TERPISAH dari worker.
    -- Kasih tau caranya, biar gak bingung pas 'velium stop' keliatan gak mempan.
    do
        local lain = sh("pgrep -f 'velium_worker.lua' | wc -l") or ""
        local n = tonumber(lain:match("%d+")) or 0
        if n > 1 then
            warn("Ada " .. n .. " proses velium jalan (mungkin `cari`/`ukur`/`pantau`).")
            info("Kalau gak mati juga:  pkill -9 -f velium_worker.lua")
        end
    end
    info("Minta berhenti ke pid " .. pid .. "...")
    local f = io.open(STOP_FILE, "w"); if f then f:write(tostring(os.time())); f:close() end

    -- worker ngecek flag tiap putaran (poll_sec, bawaan 5 detik).
    -- Kasih waktu lebih, siapa tau lagi di tengah buka client.
    for i = 1, 30 do
        os.execute("sleep 2")
        if not pid_hidup(pid) then
            ok("Berhenti baik-baik.")
            hapus(STOP_FILE)
            return
        end
        io.write(C.D.."   nungguin... "..(i*2).."s\r"..C.N); io.flush()
    end

    print()
    warn("60 detik gak mati juga. Dipaksa.")
    sh_silent("kill -9 " .. pid)
    sh_silent("pkill -9 -f 'lua.*velium_worker.lua'")
    sh_silent("termux-notification-remove velium_worker")
    sh_silent("termux-wake-unlock")
    hapus(PID_FILE); hapus(STOP_FILE)
    ok("Dimatiin paksa.")
    return
end

-- ============================================================
-- v4.84: perintah yang GAK DIKENAL jangan diem-diem nyalain worker. Dulu
-- `velium intip ...` di worker versi lama malah bikin worker nyala -- keliatan
-- kayak perintahnya "gagal aneh", padahal cuma belum ada di versi itu.
-- v5.23: `velium pasang` -- SEMUA isi pasang.sh dipindah ke sini, biar cuma ada
-- SATU berkas yang perlu di-push & diurus.
--
-- Yang gak bisa dipindah cuma satu: masang `lua` itu sendiri. Di Termux polos
-- Lua belum ada, jadi berkas .lua gak bisa jalan buat masang Lua. Makanya
-- perintah pemasangannya jadi satu baris:
--
--   pkg install lua54 curl -y && curl -sL <REPO>/velium_worker.lua -o ~/velium_worker.lua && lua5.4 ~/velium_worker.lua pasang
--
-- Sisanya (izin penyimpanan, paket lain, cek root, pintasan, kalibrasi tombol,
-- kunci API, auto-jalan) dikerjain di sini.
-- v9.208: `velium buka N` -- TES buka N client sebagai TIM 1 (loop utama). Buat cek
-- device kuat berapa client (mis. 10, 15, 20). Set TIM1_AKHIR = N, terus jalan
-- persis kayak `velium` biasa (pasang): buka CHUNK 5 (5+5+..., 90s antar chunk),
-- grid otomatis (N = 5 kolom x ceil(N/5) baris), semua client jalan loop utama.
-- Contoh: `velium buka 15`  -> tim 1 = 1-15. `velium buka 20` -> tim 1 = 1-20.
if PERINTAH == "pasang" then
    -- v5.40: pakai konstanta yang sama kayak tulis_skrip_up -- biar gak ada
    -- dua alamat repo yang bisa beda diam-diam.
    local REPO = REPO_WORKER
    local RUMAH = os.getenv("HOME") or "."
    local PREFIX = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"

    local function jalan(cmd) os.execute(cmd) end
    local function baca(cmd)
        local h = io.popen(cmd .. " 2>/dev/null")
        if not h then return "" end
        local o = h:read("*all") or ""
        h:close()
        return o
    end
    local function ada_perintah(nama)
        return baca("command -v " .. nama):match("%S") ~= nil
    end
    local function tanya(teks, bawaan)
        io.write(C.Y .. "? " .. teks .. C.N)
        if bawaan and bawaan ~= "" then io.write(C.D .. " [" .. bawaan .. "]" .. C.N) end
        io.write(": "); io.flush()
        local j = io.read()
        if j == nil or j == "" then return bawaan or "" end
        return j
    end

    print(C.BOLD .. C.C .. "\n=== VELIUM PASANG (v" .. VERSION .. ") ===\n" .. C.N)

    -- 1. izin penyimpanan -- buat nulis autoexec Delta + baca berkas lisensi
    local adaStorage = baca("ls -d " .. RUMAH .. "/storage"):match("%S")
    if not adaStorage then
        info("Minta izin penyimpanan (bakal muncul kotak izin -- tap IZINKAN)")
        jalan("termux-setup-storage")
        jalan("sleep 3")
    end
    if baca("ls -d " .. RUMAH .. "/storage"):match("%S") then ok("Izin penyimpanan ada")
    else warn("Izin penyimpanan belum -- autoexec mungkin gagal") end

    -- 2. paket sisanya (lua & curl udah ada, kan dipakai buat nyampe sini)
    info("Pasang termux-api + coreutils + figlet (agak lama di RF, sabar)")
    jalan("pkg install termux-api coreutils figlet -y >/dev/null 2>&1")
    if ada_perintah("mkfifo") then ok("mkfifo siap (shell root tetap bisa dipakai)")
    else warn("mkfifo gak ada -- shell root tetap bakal balik ke cara lama") end
    if ada_perintah("termux-clipboard-get") then ok("termux-api siap (papan klip kebaca)")
    else warn("termux-api gak ada -- `velium key` gak bisa ambil link dari papan klip") end
    if ada_perintah("figlet") then ok("figlet siap (banner startup)")
    else warn("figlet gak ada -- banner pakai teks polos (pasang: pkg install figlet)") end

    -- 3. root
    if baca("su -c 'echo ok'"):find("ok", 1, true) then
        ok("Root jalan")
    else
        warn("Root GAK jalan. Worker butuh root buat buka/tutup client Roblox.")
        warn("Buka root manager di RF, kasih izin buat Termux, terus ulangi.")
    end

    -- 4. kalibrasi tombol key -- ini yang paling ngirit waktu.
    -- Isinya pecahan per UKURAN JENDELA, jadi kalau semua RF layarnya sama,
    -- satu berkas kepakai di semua RF. Push sekali, RF baru langsung bisa.
    local jalurTap = RUMAH .. "/" .. TAP_FILE
    if not io.open(jalurTap, "r") then
        info("Ambil kalibrasi tombol key (" .. TAP_FILE .. ") -- opsional")
        jalan(("curl -fsSL '%s/%s?t=%d' -o '%s.baru' 2>/dev/null")
            :format(REPO, TAP_FILE, os.time(), jalurTap))
        local f = io.open(jalurTap .. ".baru", "r")
        local isi = f and f:read("*all") or ""
        if f then f:close() end
        if isi:match("%d+x%d+%s+[%d.]+%s+[%d.]+") then
            os.rename(jalurTap .. ".baru", jalurTap)
            local n = 0
            for _ in isi:gmatch("[^\n]+") do n = n + 1 end
            ok("Kalibrasi keunduh (" .. n .. " ukuran jendela)")
        else
            os.remove(jalurTap .. ".baru")
            warn("Belum ada " .. TAP_FILE .. " di GitHub -- nanti kalibrasi sendiri:")
            warn("   velium catat clienu <jumlah-client>")
        end
    else
        ok("Kalibrasi udah ada")
    end

    -- 5. pintasan: velium + up
    local LUA = ada_perintah("lua5.4") and "lua5.4" or "lua"
    local f1 = io.open(PREFIX .. "/bin/velium", "w")
    if f1 then
        -- v9.106: launcher LOOP (bukan exec). Worker exit + flag ~/.velium_restart ada
        -- -> loop jalanin worker LAGI (versi baru). Termux TETEP idup, gak ke prompt $.
        -- Auto-update worker pakai ini: download versi baru -> set flag -> exit -> loop.
        f1:write("#!" .. PREFIX .. "/bin/sh\n")
        f1:write('cd "$HOME"\n')
        f1:write('while true; do\n')
        f1:write('  ' .. LUA .. ' velium_worker.lua "$@"\n')
        f1:write('  if [ -f "$HOME/.velium_restart" ]; then\n')
        f1:write('    rm -f "$HOME/.velium_restart"\n')
        f1:write('    echo "[velium] restart sesi (update versi baru)..."; sleep 1; continue\n')
        f1:write('  fi\n')
        f1:write('  break\n')
        f1:write('done\n')
        f1:close()
        jalan("chmod +x " .. PREFIX .. "/bin/velium"); jalan("cp " .. PREFIX .. "/bin/velium " .. PREFIX .. "/bin/zenx 2>/dev/null; chmod +x " .. PREFIX .. "/bin/zenx 2>/dev/null")
    end
    -- `up`: dibikin lewat fungsi yang sama kayak yang dipanggil pas worker
    -- nyala -- biar isinya gak pernah beda antara RF baru dan RF lama.
    tulis_skrip_up(true)
    ok("Pintasan dibikin: velium (jalanin) + up (update worker)")

    -- 6. kunci API bypass.vip. SENGAJA ditanya di sini, bukan ditulis di worker
    -- -- worker di-push ke GitHub publik, kalau kuncinya di dalam situ siapa pun
    -- bisa baca & ngabisin kuota.
    print()
    info("Kunci API bypass.vip (buat `velium key` -- bypass key Delta)")
    info("Enter = lewat, bisa diisi nanti: velium key set <APIKEY>")
    local apikey = tanya("Kunci API", "")
    if apikey ~= "" then
        if io.open(CONFIG_FILE, "r") then
            local sukses, sebab = config_set_bypass(apikey)
            if sukses then ok("Kunci API kesimpen di " .. CONFIG_FILE)
            else err("Gagal: " .. tostring(sebab)) end
        else
            -- config belum ada (setup belum jalan) -- simpen dulu, dipasang
            -- otomatis begitu wizard selesai
            local t = io.open(RUMAH .. "/.velium_apikey_sementara", "w")
            if t then t:write(apikey); t:close()
                ok("Kunci disimpen sementara -- dipasang otomatis abis setup") end
        end
    end

    -- 7. auto-jalan pas RF nyala (butuh app Termux:Boot)
    print()
    local jb = tanya("Jalanin worker otomatis tiap RF nyala? (y/N)", "n")
    if jb:lower():sub(1, 1) == "y" then
        jalan("mkdir -p " .. RUMAH .. "/.termux/boot")
        local fb = io.open(RUMAH .. "/.termux/boot/velium", "w")
        if fb then
            fb:write("#!" .. PREFIX .. "/bin/sh\n")
            fb:write("termux-wake-lock\n")
            fb:write("export VELIUM_AUTO=1\n")
            fb:write('cd "$HOME" && ' .. LUA .. ' velium_worker.lua\n')
            fb:close()
            jalan("chmod +x " .. RUMAH .. "/.termux/boot/velium")
            ok("Auto-jalan dipasang")
            warn("Pastiin app Termux:Boot kepasang & pernah dibuka sekali.")
        end
    end

    print()
    print(C.BOLD .. C.G .. "=== SIAP ===" .. C.N)
    info("Jalanin  : velium")
    info("Matiin   : velium stop")
    info("Update   : up")
    info("Diagnosa : velium cek")
    info("Kunci key: velium lisensi  /  velium key")
    print()

    -- v5.24: gak usah nanya "jalanin sekarang?" -- langsung lanjut ke alur
    -- normal. Di situ udah ada pilihannya sendiri (Y=run / E=edit), atau
    -- langsung masuk wizard kalau config belum ada. Dulu ditanya dua kali
    -- padahal jawabannya sama.
    PERINTAH = ""
end

-- ============================================================
-- v5.25: `velium cookie` -- ekstrak .ROBLOSECURITY dari akun SENDIRI (backup /
-- pindah device). Baca kredensial milik sendiri dari storage client yg login.
-- ============================================================
-- ============================================================
-- v5.73: `velium riwayat` -- RINGKAS pola kejadian dari velium_riwayat.log.
--
-- Ini yang jawab pertanyaan yang selama ini cuma ditebak:
--   * berapa kali rejoin per jam, per akun?
--   * 267-nya nempel SETELAH rejoin (berarti rejoin-nya yang mancing),
--     atau muncul sendiri (berarti dari game/server)?
--   * ada akun yang kena terus, atau kejadiannya nyebar?
--
-- Yang ketiga penting buat mutusin arah: kalau kejadiannya numpuk di 1-2 akun,
-- itu masalah akun (limit/ban). Kalau nyebar rata, itu masalah pola rejoin
-- kita -- dan itu yang perlu diobatin.
-- ============================================================
if PERINTAH == "riwayat" then
    local f = io.open(RIW.file, "r")
    if not f then
        err("Belum ada catatan: " .. RIW.file)
        info("Berkasnya kebentuk sendiri begitu ada rejoin/kick pertama.")
        info("Biarin worker jalan beberapa jam, terus jalanin lagi.")
        return
    end

    local rows = {}
    for l in f:lines() do
        local ts, waktu, jenis, akun, ket = l:match("^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if ts then
            rows[#rows+1] = { ts = tonumber(ts), waktu = waktu,
                              jenis = jenis, akun = akun, ket = ket }
        end
    end
    f:close()

    if #rows == 0 then
        err("Catatan ada tapi kosong / formatnya gak kebaca.")
        return
    end

    local skrg = os.time()
    print(C.BOLD .. C.C .. "\n=== RIWAYAT KEJADIAN ===" .. C.N)
    info(("%d kejadian, dari %s"):format(#rows, rows[1].waktu))
    print()

    -- per jenis
    local perJenis = {}
    for _, r in ipairs(rows) do perJenis[r.jenis] = (perJenis[r.jenis] or 0) + 1 end
    print(C.BOLD .. "  PER JENIS" .. C.N)
    local jns = {}
    for k in pairs(perJenis) do jns[#jns+1] = k end
    table.sort(jns, function(a, b) return perJenis[a] > perJenis[b] end)
    for _, k in ipairs(jns) do
        print(("    %-16s %d"):format(k, perJenis[k]))
    end

    -- per akun, cuma yang rejoin
    print()
    print(C.BOLD .. "  REJOIN PER AKUN" .. C.N)
    local perAkun = {}
    for _, r in ipairs(rows) do
        if r.jenis == "REJOIN" then
            perAkun[r.akun] = perAkun[r.akun] or { n = 0, jam = {} }
            perAkun[r.akun].n = perAkun[r.akun].n + 1
            perAkun[r.akun].jam[#perAkun[r.akun].jam + 1] = r.ts
        end
    end
    local ak = {}
    for k in pairs(perAkun) do ak[#ak+1] = k end
    table.sort(ak, function(a, b) return perAkun[a].n > perAkun[b].n end)
    if #ak == 0 then
        print("    (belum ada rejoin kecatet)")
    end
    for i, k in ipairs(ak) do
        if i > 12 then print(("    ... +%d akun lagi"):format(#ak - 12)) break end
        local d = perAkun[k]
        -- jarak rata-rata antar rejoin: kalau kecil, itu tanda badai
        local rata = "-"
        if #d.jam >= 2 then
            local total = d.jam[#d.jam] - d.jam[1]
            rata = string.format("%.0f menit", (total / (#d.jam - 1)) / 60)
        end
        print(("    %-20s %2dx   jarak rata-rata: %s"):format(k:sub(1, 20), d.n, rata))
    end

    -- INI yang paling penting: kick nempel setelah rejoin?
    print()
    print(C.BOLD .. "  KICK MUNCUL BERAPA LAMA SETELAH REJOIN?" .. C.N)
    info("  kalau kebanyakan <2 menit -> rejoin-nya yang mancing kick")
    info("  kalau nyebar / lama       -> kick dari game, bukan dari kita")
    local nDekat, nJauh, nSendiri = 0, 0, 0
    for i, r in ipairs(rows) do
        if r.jenis == "KICK" then
            -- cari rejoin terakhir buat akun yang sama SEBELUM ini
            local jarak = nil
            for j = i - 1, 1, -1 do
                local q = rows[j]
                if q.akun == r.akun and q.jenis == "REJOIN" then
                    jarak = r.ts - q.ts break
                end
            end
            if not jarak then nSendiri = nSendiri + 1
            elseif jarak < 120 then nDekat = nDekat + 1
            else nJauh = nJauh + 1 end
        end
    end
    print(("    <2 menit setelah rejoin : %d"):format(nDekat))
    print(("    >2 menit setelah rejoin : %d"):format(nJauh))
    print(("    gak ada rejoin sebelumnya: %d"):format(nSendiri))
    print()
    if nDekat > (nJauh + nSendiri) then
        warn("  POLANYA: kick nempel setelah rejoin -> rejoin kita yang mancing.")
        warn("  Saran: naikin auto_rejoin_menit, dan turunin jatah rejoin.")
    elseif (nJauh + nSendiri) > nDekat and (nJauh + nSendiri) > 0 then
        ok("  POLANYA: kick MUNCUL SENDIRI -> dari game/server, bukan dari rejoin kita.")
        ok("  Saran: rejoin otomatis boleh dipertahanin; fokusin ke stabilitas join.")
    else
        info("  Belum cukup data buat nyimpulin. Biarin jalan beberapa jam lagi.")
    end

    -- 20 kejadian terakhir, mentah
    print()
    print(C.BOLD .. "  20 TERAKHIR" .. C.N)
    for i = math.max(1, #rows - 19), #rows do
        local r = rows[i]
        print(("    %s  %-14s %-18s %s"):format(
            r.waktu:sub(6), r.jenis, r.akun:sub(1, 18), r.ket))
    end
    print()
    info("Berkas mentahnya: " .. RIW.file)
    return
end

-- ============================================================
-- v5.79: `velium apk` -- unduh & pasang APK client dari Node-X.
--
-- Buat RF BARU: sepuluh client Roblox (Delta Lite) dipasang sekaligus, gak
-- usah unduh manual satu-satu terus kirim ke RF.
--
-- Alur yang kekonfirmasi dari uji lapangan:
--   1. GET /                      -> server nyetel cookie csrfToken
--   2. POST /api/unlock-folder    -> butuh header X-CSRF-Token (BUKAN cookie
--                                    doang -- itu yang bikin percobaan awal
--                                    kena "Invalid or missing CSRF token")
--   3. GET /api/folders?parentId= -> daftar berkas + ukuran + versi di NAMA
--   4. GET /api/files/<id>/download
--
-- CATATAN PENTING soal pemetaan:
-- Nama paket TERTANAM di dalam APK-nya, jadi `pm install` naruh tiap APK ke
-- slot-nya sendiri. Kita GAK milih tujuan, dan urutan unduhan gak ngaruh ke
-- kebenaran. Nomor di nama berkas ("01".."10") cuma dipakai buat NYARING dan
-- LAPORAN.
--
-- Diunduh SATU-SATU lalu langsung dipasang & dihapus -- bukan semua dulu.
-- Sepuluh APK itu ~950 MB; kalau ditumpuk, RF yang penyimpanannya pas-pasan
-- bakal penuh di tengah jalan dan semuanya sia-sia.
-- ============================================================
-- v6.20: `velium update` -- SCAN ULANG client yang kepasang, update ke config.
-- Buat RF baru (atau abis `velium download` nambah client): client baru belum
-- masuk cfg.pkgs, jadi worker gak tau ada client itu. `velium update` pindai
-- ulang + simpen. Beda dari `velium download` (yang UNDUH APK) -- ini cuma
-- DAFTAR ULANG yang udah kepasang.
if PERINTAH == "update" and arg and arg[2] == "clien" then
    -- v9.161: FORCE update SEMUA client ke versi terbaru (delta_versi.txt di GitHub),
    -- ABAIKAN cek versionName. Kenapa: nomercy = Roblox clone + Delta. Kalau Delta
    -- di-update tapi Roblox-nya versi sama, versionName GAK berubah -> `update mercy`
    -- salah bilang "udah terbaru". `update clien` maksa re-install (pm install -r).
    -- Bisa kasih versi manual: `velium update clien <versi>`.
    local cfg = load_config()
    if not cfg then err("Config gak ada. Jalanin `velium pasang` dulu."); return end
    local target = arg[3]
    if not target or target == "" then target = cek_delta_versi(cfg) end
    if not target or target == "" then
        err("Gak bisa baca versi terbaru (delta_versi.txt).\n" ..
            "   Kasih manual: velium update clien <versi>")
        return
    end
    warn(("FORCE update SEMUA client ke v%s (abaikan cek versi terpasang)"):format(target))
    update_delta_ke(cfg, target, true)
    return
end

if (PERINTAH == "update" or PERINTAH == "scan") and not (arg and (arg[2] == "mercy" or arg[2] == "clien")) then
    print(C.BOLD .. C.C .. "\n=== VELIUM UPDATE -- scan client kepasang ===\n" .. C.N)
    local cfg = load_config()
    if not cfg then
        err("Config gak ada. Jalanin `velium pasang` dulu.")
        return
    end
    info("Mindai client Roblox di HP ini...")
    local pkgs = pindai_pkgs()
    if #pkgs == 0 then
        err("Gak nemu client Roblox. Unduh dulu: velium download 48 juraganontop 1-8")
        return
    end
    -- bandingin sama config lama
    local lama = {}
    for _, p in ipairs(split(cfg.pkgs or "")) do lama[p] = true end
    local baru_ada = {}
    for _, p in ipairs(pkgs) do
        if not lama[p] then baru_ada[#baru_ada + 1] = p end
    end
    local hilang = {}
    for p in pairs(lama) do
        local masih = false
        for _, q in ipairs(pkgs) do if q == p then masih = true break end end
        if not masih then hilang[#hilang + 1] = p end
    end

    ok(("Ketemu %d client:"):format(#pkgs))
    for i, p in ipairs(pkgs) do
        local tanda = lama[p] and "" or C.G .. "  (BARU)" .. C.N
        print(("   %d. %s%s"):format(i, p:gsub("com%.roblox%.", ""), tanda))
    end
    if #baru_ada > 0 then
        ok(("%d client baru ditambah ke config"):format(#baru_ada))
    end
    if #hilang > 0 then
        warn(("%d client di config udah gak ada (dibuang): %s"):format(
            #hilang, table.concat(hilang, ", "):gsub("com%.roblox%.", "")))
    end
    if #baru_ada == 0 and #hilang == 0 then
        info("Config udah sinkron -- gak ada perubahan.")
    end

    cfg.pkgs = table.concat(pkgs, ",")
    save_config(cfg)
    ok("Config keupdate. Client siap dipakai (FORCE dari panel buat mulai).")
    return
end

-- ============================================================
-- Tiga nama, satu tempat: `download` yang dipakai sehari-hari, `dl` buat yang
-- males ngetik, `apk` DIPERTAHANIN karena RF yang udah kepasang mungkin masih
-- pakai itu. Nambah nama lain gak ada ongkosnya; ngilangin yang lama ada.
-- v9.106: tulis launcher `velium` versi LOOP (buat RF lama yg launchernya masih
-- `exec`). Dipanggil pas boot. Loop = worker exit + flag ~/.velium_restart -> jalan
-- lagi (Termux tetep idup, gak ke prompt $).
function tulis_launcher_loop()
    local PREFIX = os.getenv("PREFIX") or "/data/data/com.termux/files/usr"
    local LUA = punya_perintah("lua5.4") and "lua5.4" or "lua"
    local jalur = PREFIX .. "/bin/velium"
    local cur = io.open(jalur, "r")
    if cur then local isi = cur:read("*a") or ""; cur:close()
        if isi:find("while true", 1, true) then return end   -- udah loop
    end
    local f = io.open(jalur, "w")
    if f then
        f:write("#!" .. PREFIX .. "/bin/sh\n")
        f:write('cd "$HOME"\n')
        f:write('while true; do\n')
        f:write('  ' .. LUA .. ' velium_worker.lua "$@"\n')
        f:write('  if [ -f "$HOME/.velium_restart" ]; then\n')
        f:write('    rm -f "$HOME/.velium_restart"\n')
        f:write('    echo "[velium] restart sesi (update versi baru)..."; sleep 1; continue\n')
        f:write('  fi\n')
        f:write('  break\n')
        f:write('done\n')
        f:close()
        os.execute("chmod +x " .. shq(jalur))
        info("[boot] launcher velium di-upgrade ke mode LOOP (auto-update mulus)")
    end
end

-- v9.106: AUTO-UPDATE WORKER. Download worker dari GitHub, cek versinya. Kalau BEDA
-- + valid -> ganti file + set flag restart + return true (caller exit -> launcher
-- loop jalanin worker BARU). Termux GAK stop, cuma sesi worker yg restart.
function cek_worker_versi(cfg)
    local HOME = os.getenv("HOME") or "."
    local baru = HOME .. "/velium_worker.cek"
    local URL = REPO_WORKER .. "/velium_worker.lua?v=" .. os.time()
    os.remove(baru)
    -- v9.123: --compressed -> GitHub kirim gzip (source Lua kompres ~5:1, 784K->~150K)
    -- -> download jauh lebih cepet di RF (koneksi mobile), tanpa buang komentar.
    os.execute(("timeout 90 curl -fsSL --compressed -H 'Cache-Control: no-cache' %s -o %s 2>/dev/null"):format(
        shq(URL), shq(baru)))
    local f = io.open(baru, "r")
    if not f then return false end
    local head = f:read(3000) or ""
    f:close()
    if not head:find("VELIUM WORKER") then os.remove(baru); return false end
    local vBaru = (sh(("grep -m1 'local VERSION' %s 2>/dev/null"):format(shq(baru))) or ""):match('"([^"]+)"')
    if not vBaru or vBaru == "" or vBaru == VERSION then os.remove(baru); return false end
    local LUA = punya_perintah("lua5.4") and "lua5.4" or "lua"
    -- v9.119: FIX kutip. Dulu 'assert(loadfile(%s))' + shq(baru) -> kutip Lua jadi
    -- kutip shell, path telanjang -> SELALU gagal cek (walau file bener). Sekarang
    -- chunk pakai %q (kutip Lua) terus shq SELURUH chunk.
    local chunkCek = ("assert(loadfile(%q))"):format(baru)
    local okLua = os.execute(LUA .. " -e " .. shq(chunkCek) .. " 2>/dev/null")
    if okLua ~= true and okLua ~= 0 then
        err("[auto-update] file baru RUSAK (gak lolos cek lua) -> batal"); os.remove(baru); return false
    end
    os.execute(("mv %s %s"):format(shq(baru), shq(HOME .. "/velium_worker.lua")))
    local rf = io.open(HOME .. "/.velium_restart", "w"); if rf then rf:write("1"); rf:close() end
    info(("[auto-update] WORKER versi baru v%s (dari v%s) -> restart sesi (Termux tetep idup)"):format(vBaru, VERSION))
    return true, vBaru
end

-- ============================================================
-- v9.113: ROTASI TIM (borong stock langka pakai 2 tim gantian)
-- Tim 1 (client 1-10) loop normal. Pas API stock munculin barang yg dipilih:
-- tunggu 10s -> close tim 1 -> buka 11-15 -> jeda 60s -> buka 16-20 (grid+server
-- doang, GAK dimanage) -> balik loop utama (close tim 2 + buka tim 1). Global
-- semua biar gak makan jatah 200 lokal main-chunk.
-- ============================================================
ROTASI_STATE = "idle"    -- idle / jalan
ROTASI_CEK_TS = 0        -- ts terakhir cek API stock
ROTASI_TS = 0            -- ts terakhir rotasi selesai (cooldown)
ROTASI_SIAP_TS = 0       -- v9.116: kapan tim 1 (1-10) LENGKAP nembak server (proses idup). Rotasi baru aktif 60s setelah ini.
ROTASI_TEST_LAST = ""    -- v9.137: dedup sinyal TEST (diproses di top-loop biar cepet)
ROTASI_GO_LAST = ""      -- v9.139: dedup sinyal STOCK dari panel (real-time detect)
STOCK_LOKAL_LAST = ""    -- v9.246: dedup file stock lokal dari star_seed
ROTASI_GO_TS_PROSES = 0  -- v9.198: ts ROTASI-GO terakhir yg nyela loop (dedup interrupt)
ROTASI_SEED_TS = {}      -- v9.204: seed -> ts terakhir dirotasi. Cooldown per-seed (270s) --
                         -- dedup SERVER-SIDE: berapapun tab panel yg fire, 1 seed = 1 rotasi
                         -- per ~5 menit. Nutup "sisa sinyal panel numpuk" dari multi-tab.
ROTASI_GO_TS_SEED = {}   -- v9.230: seed -> ts ROTASI-GO terakhir yg diproses. Dedup by ts
                         -- (bukan waktu proses) -- ROTASI-GO ke-2 yg dikirim < 270s dari yg
                         -- pertama TAPI baru diproses telat (worker sibuk) tetep ke-skip.
ROTASI_GANTIAN = 0       -- v9.144: counter buat mode dunia "gantian" (W1/W2 selang-seling)

-- ambil pkg berdasar rentang slot (idx 1-based di cfg.pkgs)
function pkgs_slot(cfg, dari, sampai)
    local list = split(cfg.pkgs or "")
    local out = {}
    for i = dari, math.min(sampai, #list) do out[#out+1] = list[i] end
    return out
end

-- buka GRUP client: set grid + join server. GAK dimanage (no denyut/lisensi/rejoin).
-- v9.136: close GRUP client spesifik BARENGAN (am force-stop & ... wait dalam 1 su
-- call) -- INSTANT, gak 1-1 lambat ~5-6s/client kayak close_all. Buat rotasi cepet.
function close_grup_cepat(cfg, pkgs)
    if not pkgs or #pkgs == 0 then return 0 end
    local cmd = "su -c '"
    for _, pkg in ipairs(pkgs) do cmd = cmd .. "am force-stop " .. pkg .. " & " end
    cmd = cmd .. "wait'"
    sh_silent(cmd)
    return #pkgs
end

-- v9.229: konversi roblox:// -> WEB URL. Deep link roblox:// NYANGKUT HOME kalau app
-- udah kebuka (rejoin). Web URL + CLEAR_TOP (0x14000000) nge-reset activity Home TANPA
-- force-stop -> masuk game. Cara WC/JACKPOT dari open_one (terbukti aman, client lain OK).
function ke_url_web(cfg, url)
    local pid_w = cfg.place_id or "129343810645058"
    if not url or url == "" then return "https://www.roblox.com/games/start?placeId="..pid_w end
    if url:find("share%?code=") or url:find("/share%?") then return url end
    if url:find("privateServerLinkCode=") then
        return url:sub(1,4) == "http" and url
            or ("https://www.roblox.com/games/"..pid_w.."/x?"..url:match("(privateServerLinkCode=[%w]+)"))
    end
    local kode_w = url:match("accessCode=([%w%-]+)") or url:match("linkCode=([%w%-]+)") or url:match("code=([%w%-]+)")
    if kode_w then return "https://www.roblox.com/games/start?placeId="..pid_w.."&accessCode="..kode_w end
    return "https://www.roblox.com/games/start?placeId="..pid_w
end

function buka_grup_rotasi(cfg, pkgs, mapLink, chunkGap, cekAbort, gridBasis)
    -- v9.142: chunkGap = jeda antar chunk 5. Default 2s (tim 2 cepet). Tim 1 (loop
    -- utama) pakai 90s (buka 5 -> tunggu 90s -> buka 5 lagi).
    -- v9.225: cekAbort (opsional) = fungsi yg dicek tiap 5s pas nunggu antar chunk.
    -- Kalau return true (ada stock) -> ABORT buka sisa. Dipakai REJOIN biar stock
    -- (perintah panel) gak ke-block sama rejoin yg lama. tim 1/tim 2 rotasi = nil.
    chunkGap = tonumber(chunkGap) or 2
    -- v9.141: grid BASIS = semua pkgs yg dibuka (set PKGS_AKTIF dulu). Biar chunk 1
    -- & chunk 2 pakai layout SAMA (grid_satu -> grid_hitung(PKGS_AKTIF)). Dulu grid
    -- ngandelin PKGS_AKTIF caller -> bisa beda antar chunk -> grid tim 1 gak konsisten.
    -- v9.249: gridBasis (opsional) = pkgs FULL tim (10) buat itung grid. Biar batch
    -- 5+5 tetep di grid 10 PETAK (posisi konsisten), bukan 5 petak. Kalau gak dikasih
    -- -> pakai pkgs (backward-compat: tim 1 kirim 10 sekaligus, grid 10 udah bener).
    PKGS_AKTIF = gridBasis or pkgs
    -- v9.250: grid DIPINDAH ke DALAM loop chunk (tepat sebelum tiap chunk buka),
    -- BUKAN semua di awal. App Cloner ubah prefs window pas clone lain buka -> kalau
    -- grid semua di awal, chunk ke-2 (6-10) prefs-nya ke-timpa jadi 5-slot pas dibuka
    -- 90s kemudian. Tulis grid tepat sebelum buka -> posisi 10-slot fresh. PKGS_AKTIF
    -- tetep FULL (gridBasis/pkgs) jadi grid_satu ngitung posisi di grid penuh.
    -- v9.138: buka dalam CHUNK 5 (biar 10 client tim 1 = 5+5 staggered, gak overload
    -- + gak ke-cut). Tiap chunk 1 su call (am start batch, jeda 1s internal), gap 2s
    -- antar chunk. Client TETEP kebuka (gak di-close) -- ini cuma cara buka bertahap.
    -- v9.214: kalau total <= 7 client, buka SEMUA sekaligus (1 chunk, gak staggered).
    -- Mis. `velium buka 6` / `velium buka 7` -> langsung 1-7 barengan. > 7 = chunk 5.
    local CHUNK = (#pkgs <= 7) and #pkgs or 5
    local i = 1
    while i <= #pkgs do
        -- v9.250: grid chunk INI (posisi di grid PKGS_AKTIF penuh) tepat sebelum buka
        for j = i, math.min(i + CHUNK - 1, #pkgs) do
            pcall(function() grid_satu(cfg, pkgs[j]) end)
        end
        os.execute("sleep 1")
        local cmds = {}
        for j = i, math.min(i + CHUNK - 1, #pkgs) do
            local pkg = pkgs[j]
            local url = build_url(cfg, mapLink and mapLink[pkg] or nil)
            local url_w = ke_url_web(cfg, url)   -- v9.229: web URL biar gak nyangkut home
            if j == i then info("[buka] contoh URL join: " .. tostring(url_w):sub(1, 95)) end   -- v9.187: log 1 URL/chunk buat diagnosa dunia
            cmds[#cmds+1] = "am start -a android.intent.action.VIEW -d '" .. url_w .. "' -p " .. pkg .. " -f 0x14000000 >/dev/null 2>&1"
        end
        if #cmds > 0 then
            info(("[buka] CHUNK client %d-%d (%d client barengan)"):format(i, math.min(i + CHUNK - 1, #pkgs), #cmds))
            local batch = "su -c \"" .. table.concat(cmds, "; sleep 1; ") .. "\""
            local tmo = #cmds + 12
            local done = false
            if SHELL_AKTIF then
                done = shell_jalan(buka_bungkus_su(batch), tmo)
            end
            if not done then
                os.execute(("timeout %d %s >/dev/null 2>&1"):format(tmo, batch))
            end
        end
        i = i + CHUNK
        if i <= #pkgs then
            -- v9.211: chunk yg buka client 11+ dikasih jeda LEBIH LAMA (180s), karena
            -- device udah nanggung 10 client jalan -> buka 5 lagi lebih berat. Cuma buat
            -- open lambat (chunkGap >= 90 = tim 1 / tes); tim 2 borong (gap 2s) gak keubah.
            -- v9.213: chunk 16+ makin lama lagi (300s) -- udah 15 client jalan.
            local gap = chunkGap
            if chunkGap >= 90 then
                if     i > 15 then gap = 300   -- buka client 16-20
                elseif i > 10 then gap = 180   -- buka client 11-15
                end
            end
            info(("[buka] tunggu %ds sebelum chunk berikutnya..."):format(gap))
            -- v9.225: kalau cekAbort dikasih (REJOIN) -> cek tiap 1s (kayak borong/start
            -- paksa, responsif). Ada stock -> ABORT buka sisa. Perintah panel = UTAMA.
            local diAbort = false
            for tw = 1, gap do
                os.execute("sleep 1")
                if cekAbort and cekAbort() then diAbort = true; break end
            end
            if diAbort then
                warn("[buka] >>> ADA STOCK dari panel <<< ABORT buka sisa -> prioritas rotasi")
                break
            end
        end   -- gap antar chunk (5+5)
    end
end

-- (buka_grup_rotasi versi lama single-batch diganti chunk di atas)
function buka_grup_rotasi_LAMA(cfg, pkgs, mapLink)
    for _, pkg in ipairs(pkgs) do pcall(function() grid_satu(cfg, pkg) end) end
    os.execute("sleep 1")
    local cmds = {}
    for _, pkg in ipairs(pkgs) do
        local url = build_url(cfg, mapLink and mapLink[pkg] or nil)
        cmds[#cmds+1] = "am start -f 0x20000000 -a android.intent.action.VIEW -d '" .. url .. "' -p " .. pkg .. " >/dev/null 2>&1"
    end
    if #cmds > 0 then
        -- v9.134: JANGAN pakai sh_silent (timeout 8 -> batch ~9s ke-cut, cuma 8/10
        -- client kefire). Pakai timeout dinamis = #client + buffer. Lewat persistent
        -- shell kalau ada, else os.execute langsung.
        local batch = "su -c \"" .. table.concat(cmds, "; sleep 1; ") .. "\""
        local tmo = #cmds + 12   -- 10 am start + 9 sleep ~9s -> timeout 22
        local done = false
        if SHELL_AKTIF then
            done = shell_jalan(buka_bungkus_su(batch), tmo)
        end
        if not done then
            os.execute(("timeout %d %s >/dev/null 2>&1"):format(tmo, batch))
        end
    end
end

-- v9.114: cek API stock akurat. Format: items.{crate,gear,seed}[].{key,name,
-- nextBoundary,upcoming}. Trigger = nextBoundary barang keinginan BERUBAH naik
-- (restock baru terjadi). cfg.rotasi_barang = daftar key/name (pisah koma).
ROTASI_NB_LAST = {}    -- key barang -> nextBoundary terakhir keliat (deteksi restock)
ROTASI_LIVE_LAST = {}  -- v9.202: key barang -> qty LIVE terakhir (deteksi restock 0->>0)

function esc_pola(s)
    return (tostring(s):gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

-- ambil nextBoundary barang (cari by key dulu, terus name). nil kalau gak ketemu.
function nb_barang(body, barang)
    local be = esc_pola(barang)
    local p = body:find('"key":"' .. be .. '"')
    if not p then p = body:find('"name":"' .. be .. '"') end
    if not p then
        -- coba lower-case name (barang bisa ditulis beda case)
        local bl = esc_pola(barang:lower())
        local bodyL = body:lower()
        p = bodyL:find('"name":"' .. bl .. '"')
    end
    if not p then return nil end
    local nb = body:match('"nextBoundary":(%d+)', p)
    return nb and tonumber(nb) or nil
end

function cek_stock_rotasi(cfg)
    local mau = cfg.rotasi_barang or ""
    if mau == "" then return nil end
    local HOME = os.getenv("HOME") or "."
    local tmp = HOME .. "/.stock_cek"
    os.remove(tmp)
    -- v9.202: pakai /api/live/stock (qty LIVE BENERAN), BUKAN /predictions (prediksi
    -- -> false trigger, mis. fire_fern "muncul" padahal gak ada). Struktur:
    -- {stock:[{category,items:[{key,quantity}],restockedAt}]}.
    os.execute(("timeout 15 curl -fsSL 'https://api.gag2.gg/api/live/stock' -o %s 2>/dev/null"):format(shq(tmp)))
    local f = io.open(tmp, "r")
    if not f then return nil end
    local body = f:read("*all") or ""
    f:close()
    os.remove(tmp)
    if body == "" or not body:find("quantity", 1, true) then return nil end
    for barang in mau:gmatch("[^,]+") do
        barang = barang:gsub("^%s+", ""):gsub("%s+$", "")
        if barang ~= "" then
            -- cari "key":"<barang>" -> "quantity":N sesudahnya (item yg sama)
            local be = esc_pola(barang)
            local pos = body:find('"key":"' .. be .. '"')
            local qty = 0
            if pos then qty = tonumber(body:match('"quantity"%s*:%s*(%d+)', pos)) or 0 end
            local last = ROTASI_LIVE_LAST[barang]   -- nil pas poll pertama
            ROTASI_LIVE_LAST[barang] = qty
            -- restock = qty naik dari 0 ke >0 (baru muncul). Poll pertama (last=nil)
            -- gak fire (baseline). Yg udah keburu ada pas start -> gak fire (panel urus).
            if qty > 0 and last == 0 then
                return barang
            end
        end
    end
    return nil
end

-- SEQUENCE rotasi lengkap (blocking -- sengaja, biar dedicated).
function jalankan_rotasi(cfg, barang, mapLink, placeR)
    ROTASI_STATE = "jalan"
    -- v9.195: tim 2 borong di DUNIA SEED (placeR), bukan dunia tim 1. Kalau seed dari
    -- dunia LAIN (mis. tim 1 di W1, seed dari W2), pindah cfg.place_id sementara buat
    -- tim 2 borong, restore sebelum tim 1 balik. User: seed W2 -> tim 2 harus ke W2.
    local placeAsli = cfg.place_id
    local pindahTim2 = placeR and placeR ~= "" and placeR ~= cfg.place_id
    -- v9.194: TUNGGU 10s dulu -- biar loop utama (tim 1) beli stock-nya dulu, BARU
    -- tim 2 borong. User minta ini balik (v9.192 sempet dibuang, tapi perlu).
    warn(("[rotasi] STOCK '%s' MUNCUL -> tim 1 beli dulu, tim 2 borong 5s lagi"):format(barang))
    tambahLog_rotasi(cfg, ("STOCK %s muncul -> tim 2 dalam 5s"):format(barang))
    -- v9.196: countdown REAL-TIME di log (10, 9, 8, ...) biar keliatan mundurnya.
    -- User: tunggu 10s-nya mau real-time, bukan sleep diem.
    for det = 5, 1, -1 do   -- v9.244: countdown 10s -> 5s (tim 2 borong lebih cepet)
        info(("[rotasi] tim 2 borong dalam %ds..."):format(det))
        os.execute("sleep 1")
    end
    -- close all tim 1 (1-10) INSTANT (barengan, gak 1-1 lambat)
    info("[rotasi] close all tim 1 (client 1-10) -- barengan cepet")
    pcall(function() close_grup_cepat(cfg, pkgs_slot(cfg, 1, TIM1_AKHIR)) end)
    os.execute("sleep 1")
    -- v9.195: PINDAH dunia tim 2 (kalau seed dari dunia lain). URL join tim 2 pakai
    -- placeR (dunia seed). tim 1 udah ke-close, jadi aman ubah cfg.place_id sementara.
    if pindahTim2 then
        cfg.place_id = placeR
        warn(("[rotasi] tim 2 borong di DUNIA SEED -> place=%s (tim 1 di %s)"):format(placeR, placeAsli))
        tambahLog_rotasi(cfg, ("tim 2 pindah dunia seed: %s"):format(placeR))
    end
    -- v9.135/136: TIM 2 = ROLLING BATCH. Batch size + durasi bisa diatur panel.
    -- buka batch -> beli OPEN_SEC detik -> close batch (INSTANT) -> langsung batch
    -- berikutnya (gak nunggu 1 menit -- user minta cepet). Contoh 15 client = 3 batch.
    local total = #split(cfg.pkgs or "")
    local BATCH = math.max(1, tonumber(cfg.rotasi_batch) or 5)
    local OPEN_SEC = 80   -- v9.218: waktu beli tim 2 per batch = 80s (dari 100). Override config.
    -- v9.145: rotasi SELURUHNYA di 1 dunia (cfg.place_id). Dunia dipilih dari panel
    -- lewat command PLACE (pindahin device). Dulu v9.144 split tim 2 ke dunia beda --
    -- salah, user mau semua (tim 1+2) di 1 dunia yg ada stocknya.
    local dari = TIM1_AKHIR + 1
    local nBatch = 0
    -- v9.249: FULL tim 2 (11..total) = basis grid. Batch buka 5+5, tapi grid tetep
    -- ukuran full tim 2 (biar posisi client konsisten, gak 5 petak per batch).
    local timDuaPenuh = pkgs_slot(cfg, TIM1_AKHIR + 1, total)
    while dari <= total do
        local sampai = math.min(dari + BATCH - 1, total)
        nBatch = nBatch + 1
        PKGS_AKTIF = timDuaPenuh   -- v9.249: grid basis = full tim 2 (bukan batch)
        info(("[rotasi] BATCH %d: buka client %d-%d (borong)"):format(nBatch, dari, sampai))
        tambahLog_rotasi(cfg, ("batch %d (%d-%d) borong"):format(nBatch, dari, sampai))
        buka_grup_rotasi(cfg, pkgs_slot(cfg, dari, sampai), mapLink, nil, nil, timDuaPenuh)
        info(("[rotasi] batch %d beli... (%ds)"):format(nBatch, OPEN_SEC))
        -- v9.201: sleep OPEN_SEC TAPI cek STOCK BARU tiap detik. User: kalau ada stock
        -- baru pas lagi borong -> ABORT, ulang buat stock baru (utamain yg baru).
        local abortBaru = false
        for _ = 1, OPEN_SEC do
            os.execute("sleep 1")
            if ada_rotasi_go_baru(cfg, barang) then abortBaru = true; break end
        end
        -- close batch INSTANT + langsung batch berikutnya (gak jeda 1 menit)
        info(("[rotasi] close batch %d (client %d-%d) -- barengan cepet"):format(nBatch, dari, sampai))
        pcall(function() close_grup_cepat(cfg, pkgs_slot(cfg, dari, sampai)) end)
        if abortBaru then
            warn("[rotasi] >>> STOCK BARU dari panel <<< ABORT rotasi ini -> ulang tim 2 buat stock baru")
            tambahLog_rotasi(cfg, "ada stock baru -> abort, ulang tim 2")
            if pindahTim2 then cfg.place_id = placeAsli end
            ROTASI_STATE = "idle"
            ROTASI_TS = 0   -- gak cooldown, biar stock baru langsung ke-proses top-loop
            return
        end
        os.execute("sleep 1")
        dari = sampai + 1
    end
    os.execute("sleep 1")
    -- v9.195: RESTORE dunia tim 1 sebelum tim 1 dibuka lagi
    if pindahTim2 then
        cfg.place_id = placeAsli
        info(("[rotasi] tim 2 selesai -> balik dunia tim 1: place=%s"):format(placeAsli))
    end
    -- BALIK LOOP UTAMA: buka tim 1 lagi
    warn("[rotasi] === BALIK LOOP UTAMA (tim 1) ===")
    tambahLog_rotasi(cfg, "balik loop utama (tim 1)")
    PKGS_AKTIF = pkgs_slot(cfg, 1, TIM1_AKHIR)   -- grid tim 1 = TIM1_AKHIR-client layout
    buka_grup_rotasi(cfg, pkgs_slot(cfg, 1, TIM1_AKHIR), mapLink, 90)
    -- v9.224: set tembak_ts tim 1 (grace 240s). Abis rotasi (stock), tim 1 baru dibuka
    -- lagi -> butuh ~3 menit masuk PS baru lapor denyut. Tanpa ini, cek denyut langsung
    -- nge-rejoin tim 1 yg masih loading -> nyangkut. User: denyut nunggu loop utama 6-10.
    local tBalik = os.time()
    for _, pkg in ipairs(pkgs_slot(cfg, 1, TIM1_AKHIR)) do KICK_DIURUS["tembak_ts:" .. pkg] = tBalik end
    ROTASI_STATE = "idle"
    ROTASI_TS = os.time()
    ROTASI_SIAP_TS = 0   -- tim 1 baru dibuka lagi -> tunggu lengkap+60s sebelum rotasi lagi
    ok(("[rotasi] selesai (%d tim) -> tim 1 loop normal lagi"):format(nTim))
end

-- log rotasi ke panel (via /perintah-log atau tambahLog kalau in-scope). Simpel:
-- pakai lapor biasa, log udah ikut wlog (v9.109).
function tambahLog_rotasi(cfg, msg)
    -- info() udah masuk LOG_KIRIM (v9.109) -> keliatan di panel. Cukup ini.
    info("[rotasi] " .. msg)
end

-- v9.122: helper -- pas rotasi_on, pkg tim 2 (11-20) HARUS dilewat (standby).
-- return true = LEWAT (jangan sentuh). Cache tim1 set per cfg.pkgs.
ROT_TIM1 = nil
function rotasi_lewat(cfg, pkg)
    if not cfg.rotasi_on then return false end
    if not ROT_TIM1 or ROT_TIM1._src ~= (cfg.pkgs or "") then
        ROT_TIM1 = { _src = cfg.pkgs or "" }
        local l = split(cfg.pkgs or "")
        for i = 1, math.min(TIM1_AKHIR, #l) do ROT_TIM1[l[i]] = true end   -- v9.206: TIM1_AKHIR (bukan 10)
    end
    return not ROT_TIM1[pkg]
end

-- v9.163: AUTO-DETECT nama APK dari GitHub Releases API (tag worker_64). Return
-- map idx(1..20) -> browser_download_url. Robust: nama file apa aja kedeteksi,
-- gak nebak pola (yg dulu sering 404 gara-gara 64BIT vs 64.BIT / .apk.1.apk).
function daftar_apk_release(versi)
    local API = "https://api.github.com/repos/alzafabocahbocah-boop/revsy/releases/tags/worker_64"
    local HOME = os.getenv("HOME") or "."
    local tmp = HOME .. "/.rel_apk.json"
    os.remove(tmp)
    os.execute(("timeout 30 curl -fsSL -H 'User-Agent: velium' %s -o %s 2>/dev/null"):format(shq(API), shq(tmp)))
    local f = io.open(tmp, "r")
    if not f then return {} end
    local j = f:read("*a") or ""; f:close()
    os.remove(tmp)
    local map = {}
    for nama, url in j:gmatch('"name":%s*"([^"]+)".-"browser_download_url":%s*"([^"]+)"') do
        if nama:find(versi, 1, true) and nama:lower():find("%.apk") then
            -- ekstrak index: "...64.BIT.NN-..." atau "nomercyN-..."
            local idx = nama:match("BIT%.(%d+)%-") or nama:match("[Nn]omercy(%d+)%-")
            if idx then map[tonumber(idx)] = url end
        end
    end
    return map
end

-- v9.163: pola nama file (FALLBACK kalau API gagal). Udah dibenerin sesuai
-- Releases asli: 64.BIT (titik), file 10 = .apk.1.apk, sisanya .apk.apk.
function pola_apk(i, versi)
    if i <= 10 then
        local suf = (i == 10) and "apk.1.apk" or "apk.apk"
        return ("NO.MERCY.DELTA.LITE.64.BIT.%02d-%s.%s"):format(i, versi, suf)
    end
    return ("nomercy%d-%s.apk"):format(i, versi)
end

-- v9.100: FUNGSI GLOBAL update Delta ke versi target. Dipakai command
-- `velium update mercy <versi>`, auto-cek 10-menit di loop, + perintah UPDATE-DELTA
-- dari panel. Return sukses, dilewat, gagal. Global (bukan local) biar run() loop
-- bisa manggil + gak makan jatah 200 lokal.
function update_delta_ke(cfg, versiBaru, force)
    if not versiBaru or versiBaru == "" then return 0, 0, 0 end
    local BASE = "https://github.com/alzafabocahbocah-boop/revsy/releases/download/worker_64/"
    local HOME = os.getenv("HOME") or "."
    print(C.BOLD .. C.C .. ("\n=== UPDATE DELTA ke v%s (GitHub worker_64) ===\n"):format(versiBaru) .. C.N)
    local pkgs = split(cfg and cfg.pkgs or "")
    -- v9.169: catat client ASLI biar bisa deteksi client BARU yg ke-tambah pas
    -- update (kalau package di APK beda -> pm install -r malah NAMBAH, bukan replace).
    local pkgsAsli = {}
    for _, p in ipairs(pkgs) do pkgsAsli[p] = true end
    if #pkgs == 0 then err("Gak ada client di config. Jalanin `velium` dulu."); return 0, 0, 0 end
    local function versi_terpasang(pkg)
        local out = sh(("su -c 'dumpsys package %s 2>/dev/null | grep -m1 versionName' 2>/dev/null"):format(pkg)) or ""
        return (out:match("versionName=([%w%.%-]+)") or "")
    end
    -- v9.163: nama APK dari GitHub API (auto-detect), fallback pola kalau API gagal
    local apkMap = daftar_apk_release(versiBaru)
    local nApi = 0
    for _ in pairs(apkMap) do nApi = nApi + 1 end
    if nApi > 0 then info(("[api] %d APK v%s kedeteksi di Releases"):format(nApi, versiBaru))
    else warn("[api] gagal baca Releases -> pakai pola nama file (fallback)") end
    local TMPAPK = HOME .. "/mercy_update.apk"
    local sukses, gagal, dilewat = 0, 0, 0
    for i, pkg in ipairs(pkgs) do
        local nama = pkg:gsub("com%.roblox%.", "")
        local vNow = versi_terpasang(pkg)
        if vNow == versiBaru and not force then
            -- v9.161: force -> JANGAN skip walau versionName sama (Delta bisa beda
            -- walau versi Roblox sama). Tanpa force, skip kayak biasa.
            print(C.D .. ("[%d/%d] %s -- udah v%s, SKIP"):format(i, #pkgs, nama, versiBaru) .. C.N)
            dilewat = dilewat + 1
        else
            -- v9.163: url dari API (auto-detect), fallback ke pola nama kalau kosong
            local url = apkMap[i] or (BASE .. pola_apk(i, versiBaru))
            do
                print(C.C .. ("[%d/%d] %s "):format(i, #pkgs, nama) .. C.N ..
                    (vNow ~= "" and ("v" .. vNow) or "(blm ada)") .. " -> v" .. versiBaru)
                os.remove(TMPAPK)
                os.execute(("timeout 900 curl -# --fail -L -o %s %s"):format(
                    shq(TMPAPK), shq(url)))
                local sz = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
                if sz < 1000000 then
                    print(C.R .. ("  GAGAL download (%d byte)"):format(sz) .. C.N)
                    gagal = gagal + 1
                else
                    print(("  pasang (%.0f MB)..."):format(sz / 1024 / 1024))
                    local outf = HOME .. "/mercy_upd_pm.txt"
                    os.remove(outf)
                    os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(
                        shq(TMPAPK), shq(outf)))
                    local hasil = ""
                    for _ = 1, 150 do
                        os.execute("sleep 2")
                        local hf = io.open(outf, "r")
                        if hf then hasil = hf:read("*all") or ""; hf:close()
                            if hasil:find("Success") or hasil:find("Failure") then break end
                        end
                    end
                    os.remove(outf)
                    if tostring(hasil):find("Success") then
                        print(C.G .. "  OK" .. C.N); sukses = sukses + 1
                    else
                        print(C.R .. "  GAGAL pasang" .. C.N); gagal = gagal + 1
                    end
                end
            end
        end
    end
    os.remove(TMPAPK)
    print("")
    -- v9.169: DETEKSI client BARU yg ke-tambah (package di APK beda dari client asli
    -- -> pm install -r malah masang package baru, bukan update client lama). Auto-hapus
    -- biar gak numpuk client nyasar + warn client mana yg gak ke-update.
    local sekarang = pindai_pkgs()
    local nyasar = {}
    for _, p in ipairs(sekarang) do
        if not pkgsAsli[p] then nyasar[#nyasar+1] = p end
    end
    if #nyasar > 0 then
        warn(("%d client BARU ke-tambah (package APK BEDA dari client asli) -> auto-hapus:"):format(#nyasar))
        for _, p in ipairs(nyasar) do
            print(C.Y .. "  hapus " .. p:gsub("com%.roblox%.", "") .. C.N)
            sh(("timeout 60 su -c 'pm uninstall %s' 2>&1"):format(p))
        end
        warn("Client di config yg package-nya GAK match APK -> gak ke-update.")
        warn("Solusi: upload APK dgn package SAMA ke Releases, ATAU sesuain urutan APK.")
    end
    ok(("Selesai: %d update, %d skip (udah v%s), %d gagal%s"):format(
        sukses, dilewat, versiBaru, gagal,
        #nyasar > 0 and (", " .. #nyasar .. " nyasar dihapus") or ""))
    return sukses, dilewat, gagal
end

-- v9.103: download+install client SLOT tertentu (dari panel, checklist). slotStr =
-- "19,20" -> download nomercy19, nomercy20 doang. Buat nambah client baru tanpa
-- download ulang semua. Global biar run() loop bisa manggil.
function download_delta_slot(cfg, slotStr, versi)
    versi = (versi and versi ~= "") and versi or "2.731.944"
    local BASE = "https://github.com/alzafabocahbocah-boop/revsy/releases/download/worker_64/"
    local HOME = os.getenv("HOME") or "."
    local slots = {}
    for s in tostring(slotStr or ""):gmatch("%d+") do slots[#slots+1] = tonumber(s) end
    if #slots == 0 then err("[download-slot] gak ada slot"); return 0, 0 end
    -- v9.163: pola udah dibenerin -> pakai pola_apk global (64.BIT, file 10 spesial)
    local function namaFile(n) return pola_apk(n, versi) end
    print(C.BOLD .. C.C .. ("\n=== DOWNLOAD CLIENT SLOT: %s ===\n"):format(table.concat(slots, ",")) .. C.N)
    local TMPAPK = HOME .. "/mercy_slot.apk"
    local sukses, gagal = 0, 0
    for _, n in ipairs(slots) do
        local nama = namaFile(n)
        print(C.C .. ("[slot %d] "):format(n) .. C.N .. nama:sub(1, 40) .. "...")
        os.remove(TMPAPK)
        os.execute(("timeout 900 curl -# --fail -L -o %s %s"):format(shq(TMPAPK), shq(BASE .. nama)))
        local sz = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
        if sz < 1000000 then
            print(C.R .. ("  GAGAL download (%d byte) -- cek nama/versi di Releases"):format(sz) .. C.N)
            gagal = gagal + 1
        else
            print(("  pasang (%.0f MB)..."):format(sz / 1024 / 1024))
            local outf = HOME .. "/mercy_slot_pm.txt"
            os.remove(outf)
            os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(shq(TMPAPK), shq(outf)))
            local hasil = ""
            for _ = 1, 150 do
                os.execute("sleep 2")
                local hf = io.open(outf, "r")
                if hf then hasil = hf:read("*all") or ""; hf:close()
                    if hasil:find("Success") or hasil:find("Failure") then break end
                end
            end
            os.remove(outf)
            if tostring(hasil):find("Success") then print(C.G .. "  OK" .. C.N); sukses = sukses + 1
                DELTA_SLOT_DL[n] = true   -- v9.104: catat slot ini udah didownload
            else print(C.R .. "  GAGAL pasang" .. C.N); gagal = gagal + 1 end
        end
    end
    os.remove(TMPAPK)
    print("")
    ok(("Selesai slot: %d pasang, %d gagal"):format(sukses, gagal))
    return sukses, gagal
end

-- v9.100: baca delta_versi.txt dari GitHub (versi Delta terbaru yg mau dipasang).
-- Return versi string (trimmed) atau nil kalau gagal/kosong.
function cek_delta_versi(cfg)
    local URL = "https://raw.githubusercontent.com/wardz25/velium-worker/main/delta_versi.txt?v=" .. os.time()
    local HOME = os.getenv("HOME") or "."
    local tmp = HOME .. "/.delta_versi_cek"
    os.remove(tmp)
    os.execute(("timeout 20 curl -fsSL %s -o %s 2>/dev/null"):format(shq(URL), shq(tmp)))
    local r = nil
    local f = io.open(tmp, "r")
    if f then r = f:read("*a"); f:close() end
    os.remove(tmp)
    if not r then return nil end
    local v = tostring(r):gsub("%s+", "")   -- buang spasi/newline
    if v == "" or #v > 20 then return nil end
    return v
end

if PERINTAH == "update" and (arg and arg[2] == "mercy") then
    -- v9.53: UPDATE DELTA ke versi baru (manual). `velium update mercy 2.741.0`.
    local versiBaru = arg and arg[3]
    if not versiBaru or versiBaru == "" then
        err("Kasih versi: velium update mercy <versi>\n" ..
            "   contoh: velium update mercy 2.741.0")
        return
    end
    -- v9.162: FIX -- dulu pake `cfg` yg NIL (gak di-load) -> selalu "gak ada
    -- client di config" walau scan berhasil. Load config dulu kayak handler lain.
    local cfg = load_config()
    if not cfg then err("Config gak ada. Jalanin `velium pasang` dulu."); return end
    -- v9.168: FORCE (param true) -> update walau versi sama. User: "walaupun udah
    -- ke-update gpp update lagi aja". versionName Roblox gak berubah walau Delta
    -- baru -> tanpa force ke-skip terus.
    update_delta_ke(cfg, versiBaru, true)
    return
end

if PERINTAH == "download" and (arg and arg[2] == "mercy") then
    -- v6.79: DOWNLOAD DELTA NO MERCY dari GITHUB RELEASES (tag worker_64).
    -- github.com di-whitelist -> pasti jalan (beda dari gofile yg kena premium).
    -- 10 APK, nama pola: NO.MERCY.DELTA.LITE.64BIT.0N-2.731.944.apk.apk
    -- (file 01 beda: ...apk.1.apk). Download + pasang satu-satu.
    local BASE = "https://github.com/alzafabocahbocah-boop/revsy/releases/download/worker_64/"
    local HOME = os.getenv("HOME") or "."
    print(C.BOLD .. C.C .. "\n=== DOWNLOAD MERCY (GitHub Releases worker_64) ===\n" .. C.N)

    -- v9.163: pola udah dibenerin (64.BIT, file 10 = .apk.1.apk) + versi dari
    -- delta_versi.txt (bukan hardcoded lama). client 1-20.
    local versiDL = cek_delta_versi(cfg) or "2.733.988"
    -- v9.257: FIX -- dulu HARDCODE `for n=1,20` -> arg[3] ("1-6"/"1-10") DIABAIKAN,
    -- selalu download SEMUA 20. Sekarang parse arg[3]: "1-6" / "1,2,3" / kosong=semua.
    local function parseSlot(s, maks)
        local set = {}
        s = tostring(s or ""):gsub("%s+", "")
        if s == "" then for n = 1, maks do set[n] = true end return set end   -- kosong = semua
        for bagian in s:gmatch("[^,]+") do
            local a, b = bagian:match("^(%d+)%-(%d+)$")
            if a then
                a, b = tonumber(a), tonumber(b)
                for n = a, b do if n >= 1 and n <= maks then set[n] = true end end
            else
                local n = tonumber(bagian)
                if n and n >= 1 and n <= maks then set[n] = true end
            end
        end
        return set
    end
    local pilihan = parseSlot(arg[3], 20)
    local files, slotMap = {}, {}   -- slotMap[i] = nomor slot asli (buat map package bener)
    for n = 1, 20 do
        if pilihan[n] then files[#files + 1] = pola_apk(n, versiDL); slotMap[#files] = n end
    end
    if #files == 0 then
        err("Gak ada slot valid dari '" .. tostring(arg[3] or "") .. "'.")
        info("Contoh: velium download mercy 1-6   |   1,2,3   |   kosong = semua 20")
        return
    end
    if arg[3] and arg[3] ~= "" then
        info(("Slot dipilih: %s (%d client)"):format(tostring(arg[3]), #files))
    end

    ok(("%d APK dari GitHub Releases. Download + pasang (skip yg udah keinstall)...\n"):format(#files))
    -- v9.99: map APK -> package client (urut: file 1 -> pkgs[1], dst). Cek udah
    -- keinstall belum -> kalau udah, SKIP (gak download ulang, hemat kuota+waktu).
    local pkgsList = split(cfg and cfg.pkgs or "")
    local TMPAPK = HOME .. "/mercy_unduh.apk"
    local sukses, gagal, dilewat = 0, 0, 0
    for i, nama in ipairs(files) do
        print(C.C .. ("[%d/%d] "):format(i, #files) .. C.N .. nama:sub(1,40) .. "...")
        -- cek client ke-i udah keinstall? (package dari config, urut sama file)
        -- v9.257: pakai slotMap[i] (nomor slot ASLI), bukan i -- biar range "5-10"
        -- gak ketuker package (files[1]=slot5 -> harus pkgsList[5], bukan pkgsList[1]).
        local pkgIni = pkgsList[slotMap[i]]
        if pkgIni and pkgIni ~= "" then
            local ada = sh(("su -c 'pm list packages %s 2>/dev/null' 2>/dev/null"):format(pkgIni)) or ""
            if ada:find("package:" .. pkgIni, 1, true) then
                print(C.G .. "  udah keinstall (" .. pkgIni .. ") -> SKIP" .. C.N)
                dilewat = dilewat + 1
                goto lanjut_mercy
            end
        end
        os.remove(TMPAPK)
        -- v6.80: SAMAIN dengan curl node-x biar progress bar (garis-garis) muncul.
        -- KUNCI: stderr JANGAN dibuang (2>/dev/null) -- curl nulis bilah progress
        -- ke stderr; kalau dibuang, bilahnya ilang. -# bilah ringkas, --fail biar
        -- gagal kalau HTTP error (gak simpen HTML), -L ikutin redirect GitHub->CDN,
        -- timeout 900 jaga-jaga. os.execute (bukan sh_silent yg buang output).
        os.execute(("timeout 900 curl -# --fail -L -o %s %s"):format(
            shq(TMPAPK), shq(BASE .. nama)))
        local sz = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
        if sz < 1000000 then
            print(C.R .. ("  GAGAL download (%d byte)"):format(sz) .. C.N)
            -- tampilin awal file (mungkin html error) buat diagnosa
            local awal = sh(("head -c 120 %s 2>/dev/null"):format(shq(TMPAPK))) or ""
            if awal:match("%S") then info("    " .. awal:gsub("%s+"," "):sub(1,80)) end
            gagal = gagal + 1
        else
            print(("  pasang (%.0f MB)..."):format(sz / 1024 / 1024))
            local outf = HOME .. "/mercy_pm.txt"
            os.remove(outf)
            os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(
                shq(TMPAPK), shq(outf)))
            local hasil = ""
            for _ = 1, 150 do
                os.execute("sleep 2")
                local hf = io.open(outf, "r")
                if hf then hasil = hf:read("*all") or ""; hf:close()
                    if hasil:find("Success") or hasil:find("Failure") then break end
                end
            end
            os.remove(outf)
            if tostring(hasil):find("Success") then
                print(C.G .. "  OK" .. C.N); sukses = sukses + 1
            else
                print(C.R .. "  GAGAL pasang" .. C.N)
                info("    " .. tostring(hasil):gsub("%s+", " "):sub(1, 90))
                gagal = gagal + 1
            end
        end
        ::lanjut_mercy::
    end
    os.remove(TMPAPK)
    print("")
    ok(("Selesai: %d pasang, %d gagal, %d dilewat (udah keinstall)"):format(sukses, gagal, dilewat))
    return
end

-- v9.105: download+install SATU apk dari Releases worker_64 by NAMA FILE (generik).
-- Dipakai panel DOWNLOAD-APK:<nama> -> VPN, Termux:Boot, apapun. Global.
function download_apk_url(cfg, namaFile, label)
    if not namaFile or namaFile == "" then err("[apk] nama file kosong"); return false end
    local BASE = "https://github.com/alzafabocahbocah-boop/revsy/releases/download/worker_64/"
    local HOME = os.getenv("HOME") or "."
    print(C.BOLD .. C.C .. ("\n=== DOWNLOAD %s ===\n"):format(label or namaFile) .. C.N)
    local TMPAPK = HOME .. "/apk_unduh.apk"
    os.remove(TMPAPK)
    print(C.C .. namaFile:sub(1, 50) .. C.N .. "...")
    os.execute(("timeout 900 curl -# --fail -L -o %s %s"):format(shq(TMPAPK), shq(BASE .. namaFile)))
    local sz = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
    if sz < 10000 then
        print(C.R .. ("  GAGAL download (%d byte) -- cek nama di Releases"):format(sz) .. C.N)
        os.remove(TMPAPK); return false
    end
    print(("  pasang (%.2f MB)..."):format(sz / 1024 / 1024))
    local outf = HOME .. "/apk_pm.txt"
    os.remove(outf)
    os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(shq(TMPAPK), shq(outf)))
    local hasil = ""
    for _ = 1, 150 do
        os.execute("sleep 2")
        local hf = io.open(outf, "r")
        if hf then hasil = hf:read("*all") or ""; hf:close()
            if hasil:find("Success") or hasil:find("Failure") then break end
        end
    end
    os.remove(outf); os.remove(TMPAPK)
    if tostring(hasil):find("Success") then
        ok((label or namaFile) .. " kepasang."); return true
    else
        print(C.R .. "GAGAL pasang" .. C.N)
        info(tostring(hasil):gsub("%s+", " "):sub(1, 90)); return false
    end
end

if PERINTAH == "download" and (arg and arg[2] == "vpn") then
    -- v9.98: DOWNLOAD + PASANG Cloudflare WARP (1.1.1.1) VPN dari GitHub Releases
    -- (tag worker_64). Buat RF yang butuh VPN (ganti IP / region). 1 APK doang.
    local BASE = "https://github.com/alzafabocahbocah-boop/revsy/releases/download/worker_64/"
    local NAMA = "com-cloudflare-onedotonedotonedotone-3837-66752135-ef8b2f5f382404189163d4d14c3128a8.apk"
    local HOME = os.getenv("HOME") or "."
    print(C.BOLD .. C.C .. "\n=== DOWNLOAD VPN (Cloudflare WARP 1.1.1.1) ===\n" .. C.N)
    local TMPAPK = HOME .. "/vpn_unduh.apk"
    os.remove(TMPAPK)
    print(C.C .. "[1/1] " .. C.N .. "Cloudflare WARP...")
    -- stderr JANGAN dibuang -> bilah progress curl muncul. -# ringkas, --fail biar
    -- gagal kalau HTTP error, -L ikutin redirect GitHub->CDN, timeout 900.
    os.execute(("timeout 900 curl -# --fail -L -o %s %s"):format(
        shq(TMPAPK), shq(BASE .. NAMA)))
    local sz = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
    if sz < 1000000 then
        print(C.R .. ("  GAGAL download (%d byte)"):format(sz) .. C.N)
        local awal = sh(("head -c 120 %s 2>/dev/null"):format(shq(TMPAPK))) or ""
        if awal:match("%S") then info("    " .. awal:gsub("%s+"," "):sub(1,80)) end
        os.remove(TMPAPK)
        return
    end
    print(("  pasang (%.0f MB)..."):format(sz / 1024 / 1024))
    local outf = HOME .. "/vpn_pm.txt"
    os.remove(outf)
    os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(
        shq(TMPAPK), shq(outf)))
    local hasil = ""
    for _ = 1, 150 do
        os.execute("sleep 2")
        local hf = io.open(outf, "r")
        if hf then hasil = hf:read("*all") or ""; hf:close()
            if hasil:find("Success") or hasil:find("Failure") then break end
        end
    end
    os.remove(outf); os.remove(TMPAPK)
    print("")
    if tostring(hasil):find("Success") then
        ok("Cloudflare WARP kepasang. Buka appnya, sambungin VPN-nya manual sekali.")
    else
        print(C.R .. "GAGAL pasang" .. C.N)
        info(tostring(hasil):gsub("%s+", " "):sub(1, 90))
    end
    return
end

if PERINTAH == "pasang" and (arg and arg[2] == "mercy") or (PERINTAH == "mercy") then
    -- v6.77: PASANG DELTA LITE NO MERCY dari APK yang udah didownload MANUAL.
    -- Download langsung dari gofile GAK BISA (butuh premium -- respons
    -- "error-notPremium"). Jadi: user download APK-nya via browser ke folder
    -- Download HP, worker scan + pasang semua. Path default /sdcard/Download,
    -- bisa diganti argumen: velium mercy /sdcard/folderlain
    local dir = (arg and arg[3]) or (arg and arg[2] ~= "mercy" and arg[2]) or "/sdcard/Download"
    print(C.BOLD .. C.C .. "\n=== VELIUM PASANG MERCY (dari " .. dir .. ") ===\n" .. C.N)

    -- cari semua .apk di folder itu
    local daftar = sh(("ls -1 %s/*.apk %s/*.APK 2>/dev/null"):format(dir, dir)) or ""
    local apks = {}
    for f in daftar:gmatch("[^\n]+") do
        if f:match("%S") then apks[#apks+1] = f end
    end

    if #apks == 0 then
        err("Gak nemu file .apk di " .. dir)
        info("Cara pakai:")
        info("  1. Buka gofile.io/d/SS8g6u di browser HP")
        info("  2. Download SEMUA APK ke folder Download")
        info("  3. Jalanin: velium mercy")
        info("(atau folder lain: velium mercy /sdcard/path)")
        return
    end

    ok(("Nemu %d APK. Pasang satu-satu...\n"):format(#apks))
    local HOME = os.getenv("HOME") or "."
    local sukses, gagal = 0, 0
    for i, apk in ipairs(apks) do
        local nama = apk:match("([^/]+)$") or apk
        local sz = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(apk))) or "") or 0
        print(C.C .. ("[%d/%d] "):format(i, #apks) .. C.N .. nama ..
              (" (%.0f MB) pasang..."):format(sz / 1024 / 1024))
        local outf = HOME .. "/mercy_pm.txt"
        os.remove(outf)
        os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(
            shq(apk), shq(outf)))
        local hasil = ""
        for _ = 1, 150 do
            os.execute("sleep 2")
            local hf = io.open(outf, "r")
            if hf then hasil = hf:read("*all") or ""; hf:close()
                if hasil:find("Success") or hasil:find("Failure") then break end
            end
        end
        os.remove(outf)
        if tostring(hasil):find("Success") then
            print(C.G .. "  OK" .. C.N); sukses = sukses + 1
        else
            print(C.R .. "  GAGAL" .. C.N)
            info("    " .. tostring(hasil):gsub("%s+", " "):sub(1, 90))
            gagal = gagal + 1
        end
    end
    print("")
    ok(("Selesai: %d pasang, %d gagal"):format(sukses, gagal))
    return
end

if PERINTAH == "download" or PERINTAH == "dl" or PERINTAH == "apk" then
    local NX = "https://node-x.my.id"
    -- v6.01: config GAK WAJIB buat download. RF baru (config belum dibikin)
    -- tetep bisa download client asal folder+password dikasih di argumen.
    -- cfg cuma dipakai buat: baca folder/sandi tersimpan + nyimpen balik.
    -- Kalau gak ada cfg, jalan pakai argumen aja (gak nyimpen -- gak fatal).
    local cfg = load_config()
    local adaCfg = (cfg ~= nil)
    cfg = cfg or {}

    -- folder & password: dari argumen, atau dari config
    local folderId = tonumber(arg and arg[2] or "") or tonumber(cfg.apk_folder or "") or 43
    local sandi = (arg and arg[3]) or cfg.apk_sandi or ""
    if sandi == "" then
        err("Password folder belum ada.")
        info("Pakai:  velium download <folderId> <password>")
        info("Contoh: velium download 43 Delta32")
        info("Sekali diisi, kesimpen di config buat berikutnya.")
        return
    end

    local JAR = (os.getenv("HOME") or ".") .. "/nx_cookie.txt"
    local TMPAPK = (os.getenv("HOME") or ".") .. "/nx_unduh.apk"
    os.remove(JAR)

    print(C.BOLD .. C.C .. "\n=== VELIUM DOWNLOAD -- folder " .. folderId .. " ===\n" .. C.N)

    -- ---------- 1. ambil csrfToken ----------
    info("Ambil token...")
    sh_silent(("curl -s -c %s %s -o /dev/null"):format(shq(JAR), shq(NX .. "/")))
    local tok = sh(("grep -i csrfToken %s | awk '{print $7}'"):format(shq(JAR)))
    tok = (tok or ""):gsub("%s+$", "")
    if tok == "" then
        err("csrfToken gak keset -- situsnya kejangkau gak?")
        return
    end
    ok(("token: %d karakter"):format(#tok))

    -- ---------- 2. buka kunci ----------
    local body = string.format('{"folderId":%d,"password":%s}', folderId, jstr(sandi))
    local r = sh(("curl -s -b %s -c %s -X POST %s -H %s -H %s -H %s -d %s"):format(
        shq(JAR), shq(JAR), shq(NX .. "/api/unlock-folder"),
        shq("Content-Type: application/json"),
        shq("X-CSRF-Token: " .. tok),
        shq("Referer: " .. NX .. "/folder/" .. folderId),
        shq(body)))
    if not tostring(r):find('"success"%s*:%s*true') then
        err("Buka kunci GAGAL: " .. tostring(r):sub(1, 160))
        err("  Password salah, atau folderId-nya bukan " .. folderId .. "?")
        return
    end
    ok("Folder kebuka.")

    -- password bener -> disimpen biar gak usah diketik lagi
    cfg.apk_folder, cfg.apk_sandi = folderId, sandi
    -- v6.01: simpen cuma kalau config file udah ada (RF udah dipasang).
    -- RF baru tanpa config: skip simpen -- download tetep jalan, argumen diulang lain kali.
    if adaCfg then save_config(cfg) end

    -- ---------- 3. daftar berkas ----------
    local daftar = sh(("curl -s -b %s %s"):format(
        shq(JAR), shq(NX .. "/api/folders?parentId=" .. folderId .. "&sort=newest")))
    if not tostring(daftar):find('"files"') then
        err("Daftar berkas gak kebaca.")
        return
    end

    -- kumpulin: id, nama, ukuran
    local berkas = {}
    for blok in tostring(daftar):gmatch('{"id":%d+,"folder_id".-}') do
        local fid = tonumber(blok:match('"id":(%d+)'))
        local nm  = blok:match('"filename":"([^"]*)"')
        local sz  = tonumber(blok:match('"filesize":(%d+)'))
        if fid and nm and sz then
            berkas[#berkas + 1] = { id = fid, nama = nm, ukur = sz,
                                    no = nm:match("%s(%d%d)_") or "??" }
        end
    end
    if #berkas == 0 then
        err("Nol berkas. Folder kosong, atau kuncinya gak kepakai.")
        return
    end
    -- urut pakai NOMOR di nama, bukan id -- biar laporannya kebaca urut
    table.sort(berkas, function(a, b) return a.no < b.no end)

    local versi = berkas[1].nama:match("_([%d%.]+)%.apk$") or "?"
    ok(("%d berkas, versi %s"):format(#berkas, versi))

    -- ---------- 3b. tampilin & biarin dipilih ----------
    -- Kenapa dipilih, bukan borongan: sepuluh APK itu ~950 MB dan 4-20 menit.
    -- Kalau RF cuma pakai 5 client, separuhnya kepasang jadi paket yang gak
    -- pernah dibuka -- makan ~475 MB penyimpanan percuma.
    print()
    print(C.BOLD .. "  DAFTAR CLIENT" .. C.N)
    for i, b in ipairs(berkas) do
        print(("    %2d. client %s   %.0f MB"):format(i, b.no, b.ukur / 1e6))
    end
    print()
    -- v5.89: argumen ke-4 = pilihan langsung, skip prompt. io.read() di
    -- sebagian terminal RF (VNC/panel) gak nerima ketikan -> nyangkut selamanya,
    -- Ctrl+C ke-swallow. Kasih jalan tanpa prompt:
    --   velium download 48 pw semua   -> semua
    --   velium download 48 pw 1-3     -> client 1-3
    local pilihan
    local argPilih = arg and arg[4]
    if argPilih and argPilih ~= "" then
        pilihan = (argPilih == "semua" or argPilih == "all") and "" or argPilih
        info("Pilihan dari argumen: " .. (pilihan == "" and "SEMUA" or pilihan))
    else
        io.write(C.Y .. "  Pilih nomor (1,2,3 atau 1-5) -- Enter=SEMUA, atau lewat argumen ke-4: " .. C.N)
        io.flush()
        pilihan = (io.read() or ""):gsub("%s+", "")
    end

    local dipilih = {}
    if pilihan == "" then
        for i = 1, #berkas do dipilih[i] = true end
    else
        -- "1,2,5-7" -> {1,2,5,6,7}. Rentang didukung karena "1-5" itu cara
        -- nulis paling wajar buat lima client pertama.
        for bagian in pilihan:gmatch("[^,]+") do
            local a, z = bagian:match("^(%d+)%-(%d+)$")
            if a then
                for i = tonumber(a), tonumber(z) do
                    if berkas[i] then dipilih[i] = true end
                end
            else
                local n = tonumber(bagian)
                if n and berkas[n] then dipilih[n] = true
                elseif bagian ~= "" then
                    warn(("  '%s' dilewat -- di luar 1..%d"):format(bagian, #berkas))
                end
            end
        end
    end

    local antre = {}
    for i, b in ipairs(berkas) do
        if dipilih[i] then antre[#antre + 1] = b end
    end
    if #antre == 0 then
        err("Gak ada yang dipilih.")
        return
    end

    do
        local no = {}
        for _, b in ipairs(antre) do no[#no + 1] = b.no end
        local totMB = 0
        for _, b in ipairs(antre) do totMB = totMB + b.ukur end
        ok(("%d dipilih: %s  (~%.1f GB)"):format(
            #antre, table.concat(no, ", "), totMB / 1e9))
    end
    print()

    -- ---------- 4. unduh + pasang satu-satu ----------
    local sukses, gagal = 0, {}
    for i, b in ipairs(antre) do
        -- v5.87: FIX v5.86 nembus batas 200 lokal Lua (worker mati total di baris
--        pertama). Tabel 'kandidat' diganti fungsi lokal 'coba()' yang gak
--        nambah variabel di lingkup utama. Sama akarnya kayak RRIW v5.77 --
--        file ini mepet banget ke batas, tiap lokal baru beresiko.
--
-- v5.86: FIX `velium login` "gak nemu client" padahal client lagi login akun
--        itu. Loop pencarian cuma pakai cfg.pkgs -- di RF yang config-nya
--        belum keisi, itu kosong, jadi client target (yang disebut di argumen)
--        gak pernah dicek. Sekarang client argumen masuk kandidat pertama.
--        Plus pesan dibedain: "client login akun LAIN" vs "gak ada cookie".
--
-- v5.85: `velium login` CEK cookie hidup dulu sebelum inject.
--        Endpoint users.roblox.com/v1/users/authenticated -- bedain
--        alive/dead/captcha/ban, karena tindakannya beda (captcha bisa
--        di-solve, ban nggak, dead perlu login ulang). Status disetor ke CF
--        (/cookie-status) biar panel bisa nampilin akun mana kena apa --
--        kayak Pandora yang lapor "cookie invalid" pas start.
--        Header Cookie ditulis ke berkas dulu (bukan langsung di baris
--        perintah) -- cookie 1171 char bisa nembus batas panjang argumen.
--
-- v5.84: `velium login <akun>` -- login client pakai cookie via SQL UPDATE.
--        Cara kekonfirmasi (diuji manual berkali-kali): tulis cookie ke
--        app_webview/Cookies lewat sqlite3 UPDATE (BUKAN cp -- cp bikin journal
--        SQLite gak konsisten, Roblox anggap rusak -> CREATE ACCOUNT), terus
--        buka pakai `am` (BUKAN panel -- panel nimpa cookie kita duluan).
--        Cookie diambil sekali dari client yang login akun itu, disetor ke CF,
--        seterusnya dipakai ulang.
--        uname buat nyocokin akun DI-DECODE base64 dulu (terkubur di tengah
--        cookie) -- pola teks biasa gak kena. Ketangkep pas uji.
--
-- v5.83: bilah kemajuan curl DINYALAIN. Barisnya jadi berantakan
        -- (curl nulis di baris sendiri), tapi ditukar sama hal yang lebih
        -- berguna: keliatan angkanya jalan. Unduhan 95 MB itu 1-3 menit, dan
        -- tanpa tanda apa-apa gak ada bedanya antara "lagi jalan" sama
        -- "nyangkut" -- dan itu bikin orang nunggu sia-sia atau mbatalin yang
        -- sebenernya jalan.
        print(("  [%d/%d] client %s  (%.0f MB)"):format(i, #antre, b.no, b.ukur / 1e6))

        os.remove(TMPAPK)
        -- ============================================================
        -- v5.82 FIX: unduhan JANGAN lewat sh_silent().
        --
        -- sh_silent() motong tiap perintah di `timeout 8`. Buat perintah biasa
        -- itu masuk akal -- tapi 95 MB butuh 50-100 detik, jadi tiap unduhan
        -- dipotong di detik ke-8.
        -- Gejalanya bikin salah sangka: "GAGAL unduh (13/95 MB)" keliatan kayak
        -- jaringan putus atau server nolak, padahal kita sendiri yang motong.
        -- Ukurannya beda-beda tiap kali (9, 13, 18, 21 MB) justru karena itu
        -- batas WAKTU, bukan batas ukuran.
        --
        -- os.execute langsung, dengan batas 15 menit -- cukup buat 95 MB di
        -- sambungan paling lemot, dan tetep ada rem kalau beneran nyangkut.
        -- --fail biar HTTP 4xx/5xx gak kesimpen jadi berkas sampah yang
        -- keliatan kayak unduhan berhasil.
        -- ============================================================
        local t0 = os.time()
        -- -# = bilah ringkas (bukan tabel angka penuh). 2>&1 SENGAJA gak
        -- dibuang: bilahnya ditulis curl ke stderr, jadi kalau dibuang
        -- bilahnya ikut ilang.
        os.execute(("timeout 900 curl -# --fail -b %s %s -o %s"):format(
            shq(JAR), shq(NX .. "/api/files/" .. b.id .. "/download"), shq(TMPAPK)))
        local lama_detik = os.time() - t0

        -- ukuran dicek SEBELUM dipasang. Unduhan kepotong bikin `pm install`
        -- gagal dengan pesan yang gak nyambung -- lebih baik ketauan di sini.
        local nyata = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
        if nyata < b.ukur * 0.98 then
            print(C.R .. ("      GAGAL unduh (%.0f/%.0f MB dalam %ds)"):format(
                nyata / 1e6, b.ukur / 1e6, lama_detik) .. C.N)
            gagal[#gagal + 1] = b.no .. " (unduh kepotong)"
        else
            -- v5.82: pm install juga JANGAN lewat sh() -- batas 8 detiknya
            -- kekecilan buat APK 95 MB. Kalau kepotong, hasilnya kebaca
            -- "gagal pasang" padahal pemasangannya lagi jalan.
            -- kecepatan unduh dilaporin biar bisa DIBANDINGIN antar client.
            -- Bilah kemajuan lewat gitu aja tanpa ninggalin jejak; angka ini
            -- yang bikin ketauan kalau ada satu client yang anehnya lambat.
            local laju = lama_detik > 0 and (nyata / 1e6 / lama_detik) or 0
            io.write(("      unduh OK (%.0f MB, %ds, %.1f MB/s) -- pasang... "):format(
                nyata / 1e6, lama_detik, laju))
            io.flush()

            -- v5.90: pm install di BACKGROUND + polling file hasil. Sebabnya:
            -- pm install masang APK cepat (~15s) TAPI prosesnya baru exit setelah
            -- dexopt/verify background kelar (~200s). Nunggu exit (read atau
            -- os.execute biasa) = kejebak 200s padahal APK udah kepakai di 15s.
            -- Solusi: jalanin background, redirect hasil ke file, POLLING file
            -- tiap 2 detik sampai muncul "Success"/"Failure". Begitu kelihatan,
            -- lanjut -- biarin dexopt kelar sendiri di belakang.
            local t1 = os.time()
            local outf = (os.getenv("HOME") or ".") .. "/nx_pm.txt"
            os.remove(outf)
            os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(
                shq(TMPAPK), shq(outf)))
            local hasil = ""
            for _ = 1, 150 do   -- maks 300 detik (150 x 2s)
                os.execute("sleep 2")
                local hf = io.open(outf, "r")
                if hf then
                    hasil = hf:read("*all") or ""
                    hf:close()
                    if hasil:find("Success") or hasil:find("Failure") then break end
                end
            end
            os.remove(outf)
            if tostring(hasil):find("Success") then
                print(C.G .. ("OK (%ds)"):format(os.time() - t1) .. C.N)
                sukses = sukses + 1
            else
                print(C.R .. "GAGAL" .. C.N)
                info("      " .. tostring(hasil):gsub("%s+", " "):sub(1, 90))
                gagal[#gagal + 1] = b.no .. " (pasang)"
            end
        end
        os.remove(TMPAPK)   -- langsung dihapus, jangan numpuk
    end

    -- v6.16: AUTO-RETRY client yang gagal -- LANGSUNG di sini, gak nunggu user
    -- jalanin ulang. Cuma ulang yang GAGAL (unduh kepotong / pasang gagal),
    -- yang udah sukses gak disentuh. 2 putaran retry (total 3x percobaan).
    -- Alasan: gagal biasanya karena koneksi putus sesaat (Connection reset) --
    -- ulang sekali-dua kali biasanya beres, gak perlu ngulang semua dari awal.
    local putaran_retry = 0
    while #gagal > 0 and putaran_retry < 2 do
        putaran_retry = putaran_retry + 1
        -- kumpulin nomor client yang gagal (buang keterangan "(unduh...)"/"(pasang)")
        local ulang = {}
        for _, g in ipairs(gagal) do
            local no = tostring(g):match("^(%S+)")
            if no then ulang[#ulang + 1] = no end
        end
        warn(("RETRY %d/2 -- ulang %d client yang gagal: %s"):format(
            putaran_retry, #ulang, table.concat(ulang, ", ")))
        gagal = {}   -- reset, isi lagi kalau masih gagal
        for _, b in ipairs(antre) do
            local cocok = false
            for _, no in ipairs(ulang) do if tostring(b.no) == no then cocok = true break end end
            if cocok then
                print(("  [retry] client %s  (%.0f MB)"):format(b.no, b.ukur / 1e6))
                os.remove(TMPAPK)
                local t0 = os.time()
                os.execute(("timeout 900 curl -# --fail -b %s %s -o %s"):format(
                    shq(JAR), shq(NX .. "/api/files/" .. b.id .. "/download"), shq(TMPAPK)))
                local lama_detik = os.time() - t0
                local nyata = tonumber(sh(("stat -c %%s %s 2>/dev/null"):format(shq(TMPAPK))) or "") or 0
                if nyata < b.ukur * 0.98 then
                    print(C.R .. ("      GAGAL unduh lagi (%.0f/%.0f MB)"):format(nyata/1e6, b.ukur/1e6) .. C.N)
                    gagal[#gagal + 1] = b.no .. " (unduh kepotong)"
                else
                    local laju = lama_detik > 0 and (nyata / 1e6 / lama_detik) or 0
                    io.write(("      unduh OK (%.0f MB, %ds, %.1f MB/s) -- pasang... "):format(
                        nyata / 1e6, lama_detik, laju)); io.flush()
                    local t1 = os.time()
                    local outf = (os.getenv("HOME") or ".") .. "/nx_pm.txt"
                    os.remove(outf)
                    os.execute(("(timeout 300 su -c 'pm install -r %s' > %s 2>&1) &"):format(shq(TMPAPK), shq(outf)))
                    local hasil = ""
                    for _ = 1, 150 do
                        os.execute("sleep 2")
                        local hf = io.open(outf, "r")
                        if hf then hasil = hf:read("*all") or ""; hf:close()
                            if hasil:find("Success") or hasil:find("Failure") then break end end
                    end
                    os.remove(outf)
                    if tostring(hasil):find("Success") then
                        print(C.G .. ("OK (%ds)"):format(os.time() - t1) .. C.N)
                        sukses = sukses + 1
                    else
                        print(C.R .. "GAGAL" .. C.N)
                        gagal[#gagal + 1] = b.no .. " (pasang)"
                    end
                end
                os.remove(TMPAPK)
            end
        end
    end

    os.remove(JAR)
    print()
    if #gagal == 0 then
        ok(("SEMUA %d APK kepasang (versi %s)"):format(sukses, versi))
    else
        warn(("%d kepasang, %d masih gagal setelah 3x coba: %s"):format(sukses, #gagal, table.concat(gagal, ", ")))
        info("Cek koneksi -- client sisa bisa diulang: velium download " .. folderId)
    end
    return
end

-- ============================================================
-- v5.87: FIX v5.86 nembus batas 200 lokal Lua (worker mati total di baris
--        pertama). Tabel 'kandidat' diganti fungsi lokal 'coba()' yang gak
--        nambah variabel di lingkup utama. Sama akarnya kayak RRIW v5.77 --
--        file ini mepet banget ke batas, tiap lokal baru beresiko.
--
-- v5.86: FIX `velium login` "gak nemu client" padahal client lagi login akun
--        itu. Loop pencarian cuma pakai cfg.pkgs -- di RF yang config-nya
--        belum keisi, itu kosong, jadi client target (yang disebut di argumen)
--        gak pernah dicek. Sekarang client argumen masuk kandidat pertama.
--        Plus pesan dibedain: "client login akun LAIN" vs "gak ada cookie".
--
-- v5.85: `velium login` CEK cookie hidup dulu sebelum inject.
--        Endpoint users.roblox.com/v1/users/authenticated -- bedain
--        alive/dead/captcha/ban, karena tindakannya beda (captcha bisa
--        di-solve, ban nggak, dead perlu login ulang). Status disetor ke CF
--        (/cookie-status) biar panel bisa nampilin akun mana kena apa --
--        kayak Pandora yang lapor "cookie invalid" pas start.
--        Header Cookie ditulis ke berkas dulu (bukan langsung di baris
--        perintah) -- cookie 1171 char bisa nembus batas panjang argumen.
--
-- v5.84: `velium login <akun>` -- login client pakai cookie via SQL UPDATE.
--
-- Cara ini KEKONFIRMASI jalan (diuji manual berkali-kali): cookie ditulis
-- ke app_webview/Cookies lewat sqlite3 UPDATE (BUKAN cp -- cp bikin journal
-- SQLite gak konsisten -> Roblox anggap rusak -> CREATE ACCOUNT), terus client
-- dibuka pakai `am` (BUKAN panel Pandora -- kalau lewat panel, panel nulis
-- cookie-nya sendiri duluan dan nimpa punya kita).
--
-- Alur:
--   1. cookie akun <akun> udah ada di CF? BELUM -> ambil dari client yang lagi
--      login akun itu, setor ke CF (sekali doang, seterusnya dipakai ulang).
--   2. tarik cookie dari CF
--   3. matiin client target
--   4. sqlite3 UPDATE cookies SET value=... WHERE name=.ROBLOSECURITY
--   5. buka pakai am
--
-- sqlite3 diakses via path Termux penuh -- `su` PATH-nya beda, gak liat folder
-- Termux. `command -v sqlite3` di lingkungan su gagal walau sqlite3 kepasang.
-- ============================================================
-- decode uname dari cookie Roblox. Bagian tengah (antara "|_" dan ".") itu
-- base64 protobuf yang isinya duid/uname/uid. Di-decode pakai `base64 -d`
-- (ada di Termux coreutils). Kalau gagal, balik nil -- pemanggil lanjut nyari.
-- cek cookie ke API Roblox: hidup / mati / kena verif.
-- Endpoint users.roblox.com/v1/users/authenticated -- paling ringan, cuma
-- balikin id+nama kalau cookie sah. Yang penting bukan cuma "sah/nggak" tapi
-- BEDAIN sebabnya, karena tindakannya beda:
--   alive   -> cookie oke, lanjut login
--   dead    -> cookie mati (logout/kadaluarsa) -> perlu login ulang manual
--   captcha -> kena verif bot -> bisa di-solve BlockSolve
--   ban     -> akun kena tindakan -> gak bisa diapa-apain
-- Roblox balikin 200 (alive) / 401 (dead). captcha & ban kebedain dari
-- badan responsnya, bukan cuma kode -- makanya badan ikut diperiksa.
-- v6.02: GLOBAL (bukan local) -- dipanggil dari auto-setor (lebih awal di file)
-- + gak nambah lokal (batas 200).
function cek_cookie_roblox(cookie)
    -- v6.93: guard cookie nil/kosong -> langsung "dead" (jangan write nil ->
    -- CRASH "bad argument to write"). Kejadian pas cek cookie client yang belum
    -- ada cookie (akun "?"). Dulu nil masuk ke write -> worker mati di tengah
    -- ganti akun -> ganti akun gak kelar.
    if not cookie or cookie == "" then
        return "dead", "cookie kosong/nil"
    end
    local tmp = (os.getenv("HOME") or ".") .. "/nx_ckcek.txt"
    os.remove(tmp)
    -- tulis header Cookie ke berkas biar cookie yang panjang gak kepotong di
    -- baris perintah (ada batas panjang argumen).
    local hf = io.open(tmp, "w")
    if not hf then return "error", "gak bisa nulis tmp" end
    hf:write(".ROBLOSECURITY=" .. cookie)
    hf:close()

    local alat = RIW and RIW.http and RIW.http.pilih() or "curl"
    local cmd
    if alat == "wget" then
        cmd = ("wget -qO- --server-response --timeout=15 --header=\"Cookie: $(cat %s)\" " ..
               "https://users.roblox.com/v1/users/authenticated 2>&1"):format(shq(tmp))
    else
        cmd = ("curl -s -4 -m 15 -w \"\nHTTP:%%{http_code}\" -H \"Cookie: $(cat %s)\" " ..
               "https://users.roblox.com/v1/users/authenticated 2>&1"):format(shq(tmp))
    end
    local h = io.popen(cmd)
    local out = h and h:read("*all") or ""
    if h then h:close() end
    os.remove(tmp)

    local kode = out:match("HTTP:(%d+)") or out:match("HTTP/%d%.?%d?%s+(%d+)")
    if kode == "200" and out:find('"name"') then
        local nama = out:match('"name"%s*:%s*"([^"]*)"')
        return "alive", nama
    end
    -- captcha / ban kebedain dari isi
    local low = out:lower()
    if low:find("captcha") or low:find("challenge") then return "captcha", nil end
    -- v9.237: ban = kata utuh "banned"/"terminated"/"moderated"/frasa ban, ATAU substring
    -- "ban" (buat jaga-jaga response ban yg format-nya beda). Yg penting ban ASLI ke-catch.
    if low:find("ban") or low:find("terminat") or low:find("moderat")
       or low:find("account has been") or low:find("account status") then
        return "ban", ("kode=%s"):format(kode or "?")
    end
    if kode == "401" then return "dead", nil end
    return "error", ("kode=%s"):format(kode or "?")
end

-- v7.36: GET PS LINK per akun (kayak Pandora). Fetch private-servers API pake
-- cookie akun -> ambil accessCode -> balikin "accessCode=UUID" (buat build_url).
-- Endpoint: games.roblox.com/v1/games/PLACE/private-servers?cursor=
-- Response: data[].accessCode. Akun harus UDAH punya PS (VIP server).
-- Balikin: accessCode string, atau nil + alasan.

-- v6.37: dari hasil query (bisa MULTI-BARIS kalau ada beberapa .ROBLOSECURITY
-- beda domain/path), pilih baris cookie yang PALING PANJANG = paling lengkap.
-- Dilakuin di Lua (bukan SQL ORDER BY) biar gak gantung ke nama kolom/versi
-- WebView (skema beda antar-client -- ada yang error "no such column").
function cookie_terpanjang(raw)
    if not raw or raw == "" then return "" end
    local best = ""
    for baris in (raw .. "\n"):gmatch("(.-)\n") do
        baris = baris:gsub("%s+$", "")
        if baris:find("_|WARNING") and #baris > #best then best = baris end
    end
    -- kalau gak ada yang _|WARNING (jaga-jaga), balikin baris terpanjang apa adanya
    if best == "" then
        for baris in (raw .. "\n"):gmatch("(.-)\n") do
            baris = baris:gsub("%s+$", "")
            if #baris > #best then best = baris end
        end
    end
    return best
end

-- v6.35: GLOBAL -- dipakai auto-setor cookie (lebih awal di file)
function uname_dari_cookie(ck)
    if not ck then return nil end
    local mid = ck:match("|_([A-Za-z0-9+/=_%-]+)%.")
    if not mid then return nil end
    -- base64url -> base64 standar
    mid = mid:gsub("-", "+"):gsub("_", "/")
    local pad = #mid % 4
    if pad > 0 then mid = mid .. string.rep("=", 4 - pad) end
    local h = io.popen("printf %s " .. shq(mid) .. " | base64 -d 2>/dev/null")
    local raw = h and h:read("*all") or ""
    if h then h:close() end
    -- setelah decode, uname muncul sebagai teks: "uname" + panjang + nama
    return raw:match("uname..([a-zA-Z0-9_]+)")
end

-- v7.11: VELIUM LOGIN ATAS/BAWAH/RANDOM -- auto-ambil akun dari POOL, isi client
-- KOSONG (belum ada akun). atas=RF1 ambil dari atas pool, bawah=RF2 dari bawah,
-- random=acak. Gak nabrak antar-RF (arah beda). Ulang sampai client kosong habis
-- atau pool habis (standby nunggu cookie baru).
if PERINTAH == "login" and arg and arg[2] and
   (arg[2] == "atas" or arg[2] == "bawah" or arg[2] == "random") then
    local arah = arg[2]
    local cfg = load_config()
    if not cfg then err("Config gak ada. `velium pasang` dulu."); return end
    print(C.BOLD .. C.C .. ("\n=== VELIUM LOGIN POOL (%s) ===" .. C.N):format(arah:upper()))

    local list = split(cfg.pkgs or "")
    if #list == 0 then err("Gak ada client di config."); return end

    -- cari client KOSONG (baca_username nil/kosong = belum ada akun)
    local kosong = {}
    for _, pkg in ipairs(list) do
        local u = baca_username(pkg)
        if not u or u == "" then kosong[#kosong+1] = pkg end
    end
    if #kosong == 0 then ok("Semua client udah ada akun. Gak ada yang kosong."); return end
    info(("%d client kosong: %s"):format(#kosong,
        table.concat((function() local t={} for _,k in ipairs(kosong) do t[#t+1]=k:gsub("com%%.roblox%%.","") end return t end)(), ", ")))

    -- isi tiap client kosong: ambil akun dari pool -> suntik -> masuk
    local terisi, poolHabis = 0, false
    for _, pkg in ipairs(kosong) do
        -- ambil akun dari pool (arah)
        local resp = api_post(cfg, "/pool-ambil", string.format('{"arah":%s}', jstr(arah)), "POST") or ""
        local ada = resp:find('"ada"%s*:%s*true')
        if not ada then
            warn("Pool habis -- gak ada akun siap lagi. Standby nunggu cookie baru.")
            poolHabis = true
            break
        end
        local akunP = resp:match('"akun"%s*:%s*"([^"]+)"')
        if not akunP or akunP == "" then
            warn("Respons pool aneh (gak ada akun): " .. resp:sub(1,120))
            break
        end
        local clientPend = pkg:gsub("com%.roblox%.", "")
        info(("-> %s: isi dengan %s (dari pool)"):format(clientPend, akunP))
        -- panggil velium login <akun> <client> (suntik cookie + masuk) via subprocess
        local zbin = (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium"
        os.execute(("timeout 120 %s login %s %s"):format(zbin, akunP, clientPend))
        -- verifikasi: akun beneran kepasang?
        os.execute("sleep 3")
        local uCek = baca_username(pkg)
        if uCek and uCek:lower() == akunP:lower() then
            ok(("%s <- %s BERHASIL"):format(clientPend, akunP))
            -- tandai akun kepakai (hilang dari pool)
            pcall(function()
                api_post(cfg, "/pool-status",
                    string.format('{"akun":%s,"pool":"kepakai"}', jstr(akunP)), "POST")
            end)
            terisi = terisi + 1
        else
            warn(("%s <- %s GAGAL (kebaca: %s). Balikin akun ke pool."):format(
                clientPend, akunP, uCek or "kosong"))
            -- gagal -> balikin akun ke pool (siap lagi)
            pcall(function()
                api_post(cfg, "/pool-status",
                    string.format('{"akun":%s,"pool":"siap"}', jstr(akunP)), "POST")
            end)
        end
        os.execute("sleep 2")
    end
    print("")
    ok(("Selesai: %d client keisi%s"):format(terisi, poolHabis and " (pool habis)" or ""))
    return
end

-- v7.11: VELIUM GANTI -- client yang cookie-nya KE-BAN, ganti akun dari POOL.
-- Cek tiap client: cookie ban? -> ambil akun pool (atas default) -> suntik.
-- Beda dari login pool (yang isi client KOSONG); ini ganti client BAN.
if PERINTAH == "ganti" then
    local arah = (arg and arg[2]) or "atas"
    if arah ~= "atas" and arah ~= "bawah" and arah ~= "random" then arah = "atas" end
    local cfg = load_config()
    if not cfg then err("Config gak ada. `velium pasang` dulu."); return end
    print(C.BOLD .. C.C .. "\n=== VELIUM GANTI (client cookie ban) ===" .. C.N)

    local SQg = "/data/data/com.termux/files/usr/bin/sqlite3"
    local function ckClient(p)
        local db = "/data/data/" .. p .. "/app_webview/Default/Cookies"
        local h = io.popen(("timeout 8 su -c %s 2>/dev/null"):format(shq(
            SQg .. " " .. db .. " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
        local out = h and h:read("*all") or ""
        if h then h:close() end
        out = (out or ""):gsub("%s+$", "")
        return (out ~= "" and out:find("_|WARNING")) and out or nil
    end

    local list = split(cfg.pkgs or "")
    if #list == 0 then err("Gak ada client di config."); return end

    -- cari client yang cookie-nya BAN
    info("Cek cookie tiap client (ban?)...")
    local banClient = {}
    for _, pkg in ipairs(list) do
        local ck = ckClient(pkg)
        if ck then
            local keadaan = cek_cookie_roblox(ck)
            if keadaan == "ban" then
                banClient[#banClient+1] = pkg
                info("  " .. pkg:gsub("com%.roblox%.","") .. " -> BAN")
            end
        end
    end
    if #banClient == 0 then ok("Gak ada client cookie ban. Semua aman."); return end
    info(("%d client ban -> ganti dari pool"):format(#banClient))

    local ganti, poolHabis = 0, false
    for _, pkg in ipairs(banClient) do
        local resp = api_post(cfg, "/pool-ambil", string.format('{"arah":%s}', jstr(arah)), "POST") or ""
        if not resp:find('"ada"%s*:%s*true') then
            warn("Pool habis -- gak ada akun siap. Standby nunggu cookie baru.")
            poolHabis = true; break
        end
        local akunP = resp:match('"akun"%s*:%s*"([^"]+)"')
        if not akunP or akunP == "" then warn("Respons pool aneh: " .. resp:sub(1,120)); break end
        local clientPend = pkg:gsub("com%.roblox%.", "")
        info(("-> %s (ban): ganti ke %s (dari pool)"):format(clientPend, akunP))
        local zbin = (os.getenv("PREFIX") or "/data/data/com.termux/files/usr") .. "/bin/velium"
        os.execute(("timeout 120 %s login %s %s"):format(zbin, akunP, clientPend))
        os.execute("sleep 3")
        local uCek = baca_username(pkg)
        if uCek and uCek:lower() == akunP:lower() then
            ok(("%s <- %s BERHASIL"):format(clientPend, akunP))
            pcall(function() api_post(cfg, "/pool-status",
                string.format('{"akun":%s,"pool":"kepakai"}', jstr(akunP)), "POST") end)
            ganti = ganti + 1
        else
            warn(("%s <- %s GAGAL. Balikin ke pool."):format(clientPend, akunP))
            pcall(function() api_post(cfg, "/pool-status",
                string.format('{"akun":%s,"pool":"siap"}', jstr(akunP)), "POST") end)
        end
        os.execute("sleep 2")
    end
    print("")
    ok(("Selesai: %d client diganti%s"):format(ganti, poolHabis and " (pool habis)" or ""))
    return
end

if PERINTAH == "login" then
    local cfg = load_config()
    if not cfg then err("Config gak ada. `velium pasang` dulu."); return end

    print(C.BOLD .. C.C .. "\n=== VELIUM LOGIN (suntik cookie) ===" .. C.N)
    local akun = arg and arg[2]
    if not akun or akun == "" then
        err("Akun mana?  velium login <akun>")
        info("Contoh: velium login fifinx_10")
        return
    end
    -- client target: argumen ke-3, atau client pertama di config
    local pkg = arg and arg[3]
    if pkg and not pkg:find("%.") then pkg = "com.roblox." .. pkg end
    if not pkg then
        local list = cfg.pkgs or {}
        pkg = list[1]
    end
    if not pkg then err("Client target gak ketauan. `velium login <akun> <client>`"); return end

    local SQ = "/data/data/com.termux/files/usr/bin/sqlite3"
    local DB = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"

    -- helper baca cookie dari client via SQL
    local function cookie_dari_client(p)
        local db = "/data/data/" .. p .. "/app_webview/Default/Cookies"
        local cmd = ("su -c %s 2>/dev/null"):format(
            shq(SQ .. " " .. db ..
                " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\""))
        local h = io.popen(cmd)
        local out = h and h:read("*all") or ""
        if h then h:close() end
        out = (out or ""):gsub("%s+$", "")
        return (out ~= "" and out:find("_|WARNING")) and out or nil
    end

    -- ---------- 1. cek CF udah punya cookie akun ini? ----------
    info("Cek cookie " .. akun .. " di panel...")
    local adaResp = api_get(cfg, "/cookie-satu?akun=" .. akun)
    local cookie = tostring(adaResp or ""):match('"cookie"%s*:%s*"([^"]*)"')

    if cookie and cookie:find("_|WARNING") then
        ok("Cookie udah ada di panel (dipakai ulang).")
    else
        -- belum ada -> ambil dari client yang LAGI login akun ini
        info("Belum ada di panel. Nyari client yang login " .. akun .. "...")
        -- v5.86 FIX: client TARGET (dari argumen) ikut dicek, bukan cuma
        -- cfg.pkgs. Di RF yang config-nya belum keisi, cfg.pkgs kosong -> loop
        -- gak jalan -> "gak nemu" walau client-nya JELAS lagi login akun itu.
        -- Ketangkep di lapangan: `velium login fifinx_7 client` gagal padahal
        -- client lagi login fifinx_7.
        -- v5.87: TANPA tabel 'kandidat' -- Lua batesin 200 lokal per fungsi
        -- utama dan file ini udah mepet, nambah satu bikin gagal. Cek client
        -- TARGET dulu (satu baris), baru loop cfg.pkgs.
        local ketemu = nil
        local function coba(p)
            if not p then return false end
            local ck = cookie_dari_client(p)
            if ck and uname_dari_cookie(ck) == akun then ketemu = ck; return true end
            return false
        end
        if not coba(pkg) then
            for _, p in ipairs(cfg.pkgs or {}) do
                if p ~= pkg and coba(p) then break end
            end
        end
        if not ketemu then
            -- bedain "gak ada cookie sama sekali" vs "ada tapi akun lain" --
            -- biar user tau apa yang salah.
            -- cookie ADA di target tapi akun beda? kasih tau bedanya.
            local ckT = pkg and cookie_dari_client(pkg)
            local unT = ckT and uname_dari_cookie(ckT)
            if unT then
                err(("Client login '%s', bukan '%s'."):format(unT, akun))
                info("Cookie yang mau diambil harus lagi kepakai di client target.")
            else
                err("Gak nemu client yang lagi login " .. akun .. ".")
                info("Login dulu akun itu manual di satu client, terus ulang.")
            end
            return
        end
        cookie = ketemu
        -- setor ke CF (sekali)
        info("Setor cookie ke panel...")
        local body = string.format('{"akun":%s,"cookie":%s}', jstr(akun), jstr(cookie))
        api_post(cfg, "/cookie-simpan", body)
        ok("Cookie kesimpen di panel.")
    end

    -- ---------- 2b. CEK cookie valid dulu ----------
    -- Kalau cookie mati, gak ada gunanya inject + buka client -- cuma buang
    -- waktu dan client-nya bakal CREATE ACCOUNT. Lebih baik ketauan di sini,
    -- dan statusnya disetor ke panel biar keliatan akun mana yang perlu
    -- diurus (login ulang / solve captcha).
    info("Cek cookie hidup...")
    local keadaan, ket = cek_cookie_roblox(cookie)
    -- setor status ke CF (buat panel) -- gagal setor gak fatal
    pcall(function()
        local body = string.format('{"akun":%s,"status":%s}', jstr(akun), jstr(keadaan))
        api_post(cfg, "/cookie-status", body)
    end)
    if keadaan == "alive" then
        ok("Cookie HIDUP" .. (ket and (" (" .. ket .. ")") or "") .. ".")
    elseif keadaan == "captcha" then
        err("Cookie " .. akun .. " kena VERIF/CAPTCHA.")
        info("Bisa di-solve: nanti lewat BlockSolve. Login dibatalin.")
        return
    elseif keadaan == "ban" then
        err("Cookie " .. akun .. " kena BAN/moderasi. Login dibatalin.")
        return
    elseif keadaan == "dead" then
        -- v6.32: JANGAN batalin login gara-gara cek "dead". Cek cookie sebelum
        -- login sering FALSE NEGATIF -- kena rate-limit (401/429) pas dicek
        -- berkali-kali cepat, padahal cookie HIDUP. Suntik aja, biar CLIENT yang
        -- buktiin (kalau beneran mati, client gagal masuk -> itu bukti asli).
        warn("Cek cookie " .. akun .. " bilang mati -- tapi cek sering meleset")
        warn("  (rate-limit). Tetep disuntik -- client yang buktiin.")
    else
        warn("Cek cookie gak pasti (" .. tostring(ket) .. "). Lanjut coba login.")
    end

    -- ---------- 3. matiin client ----------
    info("Matiin " .. pkg:gsub("com%.roblox%.", "") .. "...")
    sh_silent("su -c 'am force-stop " .. pkg .. "'")   -- v7.82: pakai su (root)
    os.execute("sleep 2")

    -- ---------- 4. tulis cookie via SQL ----------
    -- cookie di-escape buat SQL: kutip tunggal digandain. Tapi cookie Roblox
    -- gak pernah punya kutip tunggal (kekonfirmasi: cuma A-Z a-z 0-9 _ - | . :),
    -- jadi ini jaga-jaga.
    local ck_sql = cookie:gsub("'", "''")
    -- v6.43: cek KOLOM cookie dulu. WebView beda versi: ada yang `value`
    -- (plaintext), ada yang cuma `encrypted_value`. UPDATE ke kolom yang salah
    -- -> "no such column" -> cookie GAK kesuntik -> akun GAK ganti di RF.
    local kolInfo = io.popen(("su -c %s 2>/dev/null"):format(shq(
        SQ .. " " .. DB .. " \"PRAGMA table_info(cookies)\"")))
    local kolRaw = kolInfo and kolInfo:read("*all") or ""
    if kolInfo then kolInfo:close() end
    -- PRAGMA output tiap baris: "cid|name|type|notnull|dflt|pk"
    -- cari baris yang name-nya persis "value" (dikelilingi | )
    local adaValue = kolRaw:find("|value|") ~= nil
    local kolom = adaValue and "value" or nil

    if not kolom then
        err("Client " .. pkg:gsub("com%.roblox%.","") .. " skema cookie-nya pakai")
        err("  kolom terenkripsi (bukan 'value') -- suntik plaintext gak bisa.")
        err("  Cookie GAK kesuntik. Client ini perlu WebView versi lain.")
        return
    end

    local upd = ("%s %s \"UPDATE cookies SET " .. kolom .. "='%s' WHERE name='.ROBLOSECURITY'\""):format(
        SQ, DB, ck_sql)
    local h = io.popen(("su -c %s 2>&1"):format(shq(upd)))
    local uout = h and h:read("*all") or ""
    if h then h:close() end
    if uout and uout:find("[Ee]rror") then
        err("SQL gagal: " .. uout:sub(1, 120))
        return
    end

    -- verifikasi panjang
    local cek = io.popen(("su -c %s 2>/dev/null"):format(
        shq(SQ .. " " .. DB ..
            " \"SELECT length(" .. kolom .. ") FROM cookies WHERE name='.ROBLOSECURITY'\"")))
    local pj = cek and cek:read("*all") or ""
    if cek then cek:close() end
    pj = (pj or ""):gsub("%s+", "")

    -- v6.94: kalau UPDATE gak kena row (panjang kosong = row .ROBLOSECURITY
    -- BELUM ADA, client baru belum pernah login), INSERT row baru. UPDATE cuma
    -- ngubah row yang udah ada -- client baru gak punya -> cookie gak masuk ->
    -- "panjang ?" -> akun gak ganti. Ini sebab utama client baru gak bisa login.
    if pj == "" then
        info("Row cookie belum ada (client baru) -- INSERT baru...")
        -- v6.94: creation_utc WAJIB (NOT NULL) + last_access_utc. Pakai timestamp
        -- WebKit (mikrodetik sejak 1601). Dulu INSERT gak isi creation -> "NOT
        -- NULL constraint failed: cookies.creation" -> cookie gak masuk.
        -- Timestamp unik (creation dipakai jadi bagian primary key di sebagian
        -- skema) -> pakai waktu sekarang dalam mikrodetik WebKit.
        local nowUtc = (os.time() + 11644473600) * 1000000
        -- v6.96: CARA PALING ANDAL -- COPY row cookie yang UDAH ADA (apa pun),
        -- ganti creation_utc (unik) + host_key + name + value + expires. Ini
        -- otomatis isi SEMUA kolom NOT NULL (top_frame_site_key, dll) dari row
        -- contoh -> gak perlu nebak kolom wajib satu-satu (creation, top_frame,
        -- has_cross_site_ancestor, ...). Roblox client PASTI punya cookie lain
        -- (dari sesi WebView), jadi ada row contoh.
        local adaRow = io.popen(("su -c %s 2>/dev/null"):format(
            shq(SQ .. " " .. DB .. " \"SELECT COUNT(*) FROM cookies\"")))
        local jml = adaRow and adaRow:read("*all") or "0"
        if adaRow then adaRow:close() end
        jml = tonumber(((jml or ""):gsub("%s+",""))) or 0

        local iout = ""
        if jml > 0 then
            -- v7.01: CARA TERBUKTI (dites manual). INSERT langsung dgn SELECT dari
            -- cookie contoh (GuestData/apa pun) -- ambil kolom skema-spesifik
            -- (priority, samesite, source_scheme, is_same_party, top_frame_site_key)
            -- dari row contoh, TAPI kolom penting (creation, host, name, value,
            -- path, expires, secure) di-SET literal. creation_utc pakai WAKTU
            -- SEKARANG (WebKit us) -- BUKAN angka asal gede: Roblox anggap cookie
            -- "dari masa depan" KORUP -> HAPUS pas client buka -> balik guest.
            -- Gak sebut has_cross_site_ancestor (gak ada di sebagian skema).
            local expUtc = (os.time() + 11644473600 + 31536000) * 1000000  -- +1 taun
            local insCmd = ('%s %s "DELETE FROM cookies WHERE name=\'.ROBLOSECURITY\'; INSERT INTO cookies (creation_utc,host_key,name,%s,path,expires_utc,is_secure,is_httponly,last_access_utc,has_expires,is_persistent,priority,samesite,source_scheme,source_port,is_same_party,top_frame_site_key) SELECT %d,\'.roblox.com\',\'.ROBLOSECURITY\',\'%s\',\'/\',%d,1,1,%d,1,1,priority,samesite,source_scheme,443,is_same_party,top_frame_site_key FROM cookies LIMIT 1"'):format(
                SQ, DB, kolom, nowUtc, ck_sql, expUtc, nowUtc)
            local hf = io.popen(("su -c %s 2>&1"):format(shq(insCmd)))
            iout = hf and hf:read("*all") or ""
            if hf then hf:close() end
        else
            -- gak ada row contoh -> INSERT manual (kolom inti + wajib umum)
            local expUtc = (os.time() + 11644473600 + 31536000) * 1000000
            local ins = ('%s %s "INSERT INTO cookies (creation_utc,host_key,name,%s,path,expires_utc,is_secure,is_httponly,last_access_utc,has_expires,is_persistent,priority,samesite,source_scheme,source_port,is_same_party,top_frame_site_key) VALUES (%d,\'.roblox.com\',\'.ROBLOSECURITY\',\'%s\',\'/\',%d,1,1,%d,1,1,1,-1,2,443,0,\'\')"'):format(
                SQ, DB, kolom, nowUtc, ck_sql, expUtc, nowUtc)
            local hi = io.popen(("su -c %s 2>&1"):format(shq(ins)))
            iout = hi and hi:read("*all") or ""
            if hi then hi:close() end
        end
        if iout and iout:find("[Ee]rror") then
            warn("INSERT cookie gagal: " .. iout:sub(1,100))
        end
        -- cek ulang panjang setelah INSERT
        local cek2 = io.popen(("su -c %s 2>/dev/null"):format(
            shq(SQ .. " " .. DB ..
                " \"SELECT length(" .. kolom .. ") FROM cookies WHERE name='.ROBLOSECURITY'\"")))
        pj = cek2 and cek2:read("*all") or ""
        if cek2 then cek2:close() end
        pj = (pj or ""):gsub("%s+", "")
    end

    ok(("Cookie ketulis (panjang %s)."):format(pj ~= "" and pj or "?"))

    -- v6.40: UPDATE prefs.xml biar SINKRON sama cookie baru. Lapor status rutin
    -- baca username dari prefs.xml (murah, gak hang) -- kalau prefs ketinggalan,
    -- panel nampilin akun lama. Update sekali di sini (pas ganti) = prefs bener,
    -- lapor rutin tetep ringan. Username diambil dari cookie yang baru disuntik.
    do
        local unBaru = uname_dari_cookie(cookie)
        if unBaru and unBaru ~= "" then
            local prefsPath = "/data/data/" .. pkg .. "/shared_prefs/prefs.xml"
            -- ganti nilai <string name="username">...</string> pakai sed
            local sed = ("sed -i 's|<string name=\"username\">[^<]*</string>|<string name=\"username\">%s</string>|' %s"):format(unBaru, prefsPath)
            sh_silent("su -c " .. shq(sed))
            info("prefs.xml diupdate: username -> " .. unBaru)
        end
    end

    -- ---------- 5. buka pakai am ----------
    info("Buka client...")
    sh_silent("am start -n " .. pkg .. "/.startup.ActivityProtocolLauncher")
    ok("Login " .. akun .. " -> " .. pkg:gsub("com%.roblox%.", "") .. ". Tunggu masuk game.")
    return
end

-- v9.210: `velium buka N` (N=angka) -- TES buka N client LANGSUNG. TANPA main loop,
-- TANPA FORCE panel, TANPA rotasi, TANPA pulih state. Cuma buka N client (chunk 5,
-- grid otomatis, join place di config). Buat cek device kuat berapa client.
-- Client tetep kebuka setelah command selesai -> tutup manual / matiin app Termux.
-- Contoh: `velium buka 10`, `velium buka 15`, `velium buka 20`.
if PERINTAH == "buka" and tonumber(arg and arg[2] or "") then
    local n = math.max(1, math.min(20, math.floor(tonumber(arg[2]))))
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium` dulu buat setup."); return end
    local pkgs = pkgs_slot(cfg, 1, n)
    if #pkgs == 0 then err("Gak ada client di config."); return end
    TIM1_AKHIR = #pkgs   -- biar grid pas
    local gk = (SUSUNAN[#pkgs] and SUSUNAN[#pkgs][1]) or 5
    warn(("[TES] buka %d client LANGSUNG -- chunk 5, grid %d kolom. GAK nunggu FORCE, GAK ada rotasi."):format(#pkgs, gk))
    info("   (buka 5 -> tunggu 90s -> buka 5 lagi ... sampe " .. #pkgs .. ". Sabar.)")
    PKGS_AKTIF = pkgs
    pcall(function() buka_grup_rotasi(cfg, pkgs, nil, 90) end)
    ok(("Selesai -- %d client kebuka. Cek device kuat/RAM/lag. Tutup manual atau matiin app Termux."):format(#pkgs))
    return
end

if PERINTAH == "pantaucookie" or PERINTAH == "catatakun" then
    -- v6.26: MODE PANTAU COOKIE -- cuma catat cookie akun baru ke panel, GAK buka
    -- client / masukin game. Buat pas bikin akun manual di RF: worker ngintip
    -- client Roblox kepasang, tiap ada akun BARU login (belum kesetor), extract
    -- cookie + setor + cek hidup. Loop terus sampai Ctrl-C. Beda dari FORCE yang
    -- auto buka semua client + masukin game.
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin `velium pasang` dulu."); return end
    local SQ = "/data/data/com.termux/files/usr/bin/sqlite3"
    print(C.BOLD .. C.C .. "\n=== MODE PANTAU COOKIE (Ctrl-C buat stop) ===\n" .. C.N)
    info("Bikin akun manual di client RF -- cookie akun baru auto-kecatat ke panel.")
    info("Worker GAK buka client / masukin game di mode ini.\n")
    local sudah = {}   -- akun yang udah kesetor sesi ini
    while true do
        for _, pkg in ipairs(pindai_pkgs()) do
            if pkg_running(pkg) then
                -- v6.35: extract cookie DULU, terus ambil username DARI COOKIE
                -- (uname_dari_cookie), BUKAN prefs.xml. Sebabnya: prefs.xml bisa
                -- KETINGGALAN (masih akun lama) sedangkan cookie SQL udah akun
                -- baru -> nama & cookie GAK SINKRON (nama akun A, cookie akun B).
                -- Ambil dari cookie = pasti cocok, apa pun isi prefs.xml.
                local db = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
                -- v6.36: bisa ADA BEBERAPA baris .ROBLOSECURITY (beda domain/path);
                -- sebagian bisa kepotong/mati. Ambil yang PALING PANJANG (cookie
                -- asli paling panjang & lengkap) -> hindari yang invalid.
                local hC = io.popen(("su -c %s 2>/dev/null"):format(shq(
                    SQ .. " " .. db ..
                    " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\"")))
                local ckC = hC and hC:read("*all") or ""
                if hC then hC:close() end
                ckC = cookie_terpanjang(ckC or "")
                -- username DARI cookie (sinkron), fallback prefs.xml kalau gagal decode
                local ak = (ckC ~= "" and ckC:find("_|WARNING")) and uname_dari_cookie(ckC) or nil
                if not ak or ak == "" then ak = baca_username(pkg) end
                if ak and ak ~= "" and ak ~= "?" and not sudah[ak] then
                    if ckC ~= "" and ckC:find("_|WARNING") then
                        io.write(C.BOLD .. ak .. C.N .. "  ")
                        io.flush()
                        pcall(function()
                            api_post(cfg, "/cookie-simpan", string.format(
                                '{"akun":%s,"paket":%s,"cookie":%s}', jstr(ak), jstr(pkg), jstr(ckC)))
                        end)
                        local kead = cek_cookie_roblox(ckC)
                        pcall(function()
                            api_post(cfg, "/cookie-status", string.format(
                                '{"akun":%s,"status":%s}', jstr(ak), jstr(kead)))
                        end)
                        local warna = (kead == "alive") and C.G or (kead == "captcha") and C.Y or C.R
                        print(warna .. kead:upper() .. C.N .. C.D .. "  -> panel" .. C.N)
                        sudah[ak] = true
                    end
                end
            end
        end
        os.execute("sleep 5")   -- cek tiap 5 detik
    end
    return
end

if PERINTAH == "cekcookie" then
    -- v5.99: cek cookie SEMUA akun yang lagi login di client tim ini.
    -- Buat tiap client jalan: baca username + cookie -> cek_cookie_roblox ->
    -- setor status ke panel (/cookie-status). Dipanggil dari panel (tombol
    -- "cek" per tim) lewat perintah CEKCOOKIE, atau manual `velium cekcookie`.
    local cfg = load_config()
    if not cfg then err("Config belum ada."); return end
    local SQ = "/data/data/com.termux/files/usr/bin/sqlite3"
    print(C.BOLD .. C.C .. "\n=== CEK COOKIE HIDUP (semua akun tim) ===\n" .. C.N)
    local cek, hidup = 0, 0
    for _, pkg in ipairs(split(cfg.pkgs)) do
        if pkg_running(pkg) then
            local akun = baca_username(pkg)
            if akun and akun ~= "" and akun ~= "?" then
                -- baca cookie via SQL
                local db = "/data/data/" .. pkg .. "/app_webview/Default/Cookies"
                local cmd = ("su -c %s 2>/dev/null"):format(shq(
                    SQ .. " " .. db ..
                    " \"SELECT value FROM cookies WHERE name='.ROBLOSECURITY'\""))
                local hC = io.popen(cmd)
                local ck = hC and hC:read("*all") or ""
                if hC then hC:close() end
                ck = cookie_terpanjang(ck or "")
                if ck ~= "" and ck:find("_|WARNING") then
                    io.write(C.BOLD .. akun .. C.N .. "  ")
                    io.flush()
                    local keadaan, ket = cek_cookie_roblox(ck)
                    cek = cek + 1
                    if keadaan == "alive" then hidup = hidup + 1 end
                    -- warna status
                    local warna = (keadaan == "alive") and C.G
                        or (keadaan == "captcha") and C.Y or C.R
                    print(warna .. keadaan:upper() .. C.N ..
                          (ket and (" " .. C.D .. "(" .. ket .. ")" .. C.N) or ""))
                    -- setor ke panel
                    pcall(function()
                        local body = string.format('{"akun":%s,"status":%s}',
                            jstr(akun), jstr(keadaan))
                        api_post(cfg, "/cookie-status", body)
                    end)
                end
            end
        end
    end
    print("")
    ok(("Selesai: %d cookie dicek, %d hidup."):format(cek, hidup))
    info("Status kesetor ke panel -- cek tab Cookie.")
    return
end

if PERINTAH == "cookie" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin setup dulu."); return end

    -- Satu panggilan su per client (inget 5.3: su ~6 detik/panggilan). Timeout
    -- panjang -- grep rekursif se-data-dir bisa lama; sh() dipatok 8s -> kepotong.
    -- @FILES = bukti file mana yg punya cookie. @COOKIE = nilai yg diekstrak.
    -- Pola cookie: "_|WARNING..." lalu token [huruf/angka/_ | . : -].
    local function ambil_cookie(pkg)
        local skrip =
            'd=/data/data/' .. pkg .. '; ' ..
            'echo @FILES; ' ..
            'grep -rla "ROBLOSECURITY" "$d" 2>/dev/null; ' ..
            'echo @COOKIE; ' ..
            'grep -rhoaE "_[|]WARNING[A-Za-z0-9_|.:-]+" "$d" 2>/dev/null | sort -u | head -1'
        local cmd = "timeout 45 su -c " .. shq(skrip) .. " 2>/dev/null"
        local h = io.popen(cmd)
        if not h then return {}, nil end
        local raw = h:read("*all") or ""; h:close()
        local files, cookie, mode = {}, nil, nil
        for baris in raw:gmatch("[^\n]+") do
            if baris == "@FILES" then mode = "f"
            elseif baris == "@COOKIE" then mode = "c"
            elseif mode == "f" then files[#files+1] = baris
            elseif mode == "c" and not cookie and baris:match("_[|]WARNING") then
                cookie = baris
            end
        end
        return files, cookie
    end

    -- tentuin target
    local arg2 = (arg[2] or ""):lower()
    local targets = {}
    if arg2 == "all" then
        targets = split(cfg.pkgs)
    elseif arg2 ~= "" then
        if #arg2 == 1 then targets = { "com.roblox.clien" .. arg2 }
        else targets = { arg2 } end
    else
        for _, pkg in ipairs(split(cfg.pkgs)) do
            if pkg_running(pkg) then targets[#targets+1] = pkg end
        end
        if #targets == 0 then
            warn("Gak ada client yang kebaca jalan.")
            info("Paksa satu client   :  velium cookie <huruf>   (mis. velium cookie u)")
            info("Paksa semua kepasang:  velium cookie all")
            return
        end
    end

    print(C.BOLD .. C.C .. "\n=== EKSTRAK COOKIE (backup akun sendiri) ===\n" .. C.N)
    local OUT = "/sdcard/velium_cookies.txt"
    local hasil = {}
    for _, pkg in ipairs(targets) do
        -- v5.26: label nama akun dari prefs.xml (baca_username, sumber yg sama
        -- kayak mapping client<->akun auto-rejoin). Kalau kosong -> "?".
        local akun = baca_username(pkg) or ""
        if akun == "" then akun = "?" end
        io.write(C.BOLD .. pkg .. C.N .. "  " .. C.C .. akun .. C.N .. "  ")
        local files, cookie = ambil_cookie(pkg)
        if cookie then
            local pendek = cookie:sub(1, 28) .. "..." .. cookie:sub(-6)
            print(C.G .. "OK" .. C.N .. "  (" .. #cookie .. " char)  " .. C.D .. pendek .. C.N)
            if #files > 0 then
                print("   " .. C.D .. "dari: " .. files[1] .. (#files > 1 and (" (+" .. (#files-1) .. " file lain)") or "") .. C.N)
            end
            -- format: <akun>\t<paket>\t<cookie>  -- akun didulukan biar gampang dicocokin
            hasil[#hasil+1] = akun .. "\t" .. pkg .. "\t" .. cookie
        else
            print(C.Y .. "GAK KETEMU" .. C.N)
            if #files > 0 then
                -- ada file ber-ROBLOSECURITY tapi pola cookie gak match -> format beda
                print("   " .. C.Y .. "ada file ber-ROBLOSECURITY tapi nilainya gak ke-ekstrak:" .. C.N)
                for i = 1, math.min(#files, 3) do
                    print("   " .. C.D .. files[i] .. C.N)
                end
                print("   " .. C.D .. "kirim salah satu path ini -- formatnya beda, perlu disetel." .. C.N)
            else
                print("   " .. C.D .. "gak ada jejak ROBLOSECURITY di /data/data/" .. pkg .. C.N)
                print("   " .. C.D .. "(client login? root jalan? mungkin token disimpen beda)" .. C.N)
            end
        end
    end

    print("")
    if #hasil > 0 then
        local f = io.open(OUT, "w")
        if f then
            f:write(table.concat(hasil, "\n") .. "\n"); f:close()
            ok("Kesimpen: " .. OUT .. "  (" .. #hasil .. " cookie, format: <akun>\\t<paket>\\t<cookie>)")
            info("File ada di /sdcard -- tinggal tarik lewat RedFinger file manager / adb pull.")
            print("   " .. C.D .. "Akun '?' = prefs.xml belum ada username-nya (client baru / belum login penuh)." .. C.N)

            -- v5.27: KIRIM ke panel (CF) biar bisa diliat + copy dari panel.
            -- Di panel digerbang password; di sini worker cuma nyetor (X-Kunci).
            -- Gak fatal kalau gagal -- file lokal tetep ada sebagai cadangan.
            print("")
            info("Ngirim ke panel...")
            local kirim_ok, kirim_gagal = 0, 0
            for _, baris in ipairs(hasil) do
                local akun2, paket2, cookie2 = baris:match("^(.-)\t(.-)\t(.*)$")
                if cookie2 and cookie2 ~= "" then
                    local body = '{"akun":"' .. jstr(akun2) .. '","paket":"' .. jstr(paket2) ..
                                 '","cookie":"' .. jstr(cookie2) .. '"}'
                    local resp = api_post(cfg, "/cookie-simpan", body) or ""
                    if resp:find('"ok"%s*:%s*true') then
                        kirim_ok = kirim_ok + 1
                    elseif resp:find("belumSiap") then
                        err("Tabel 'cookies' belum ada di D1. Buat dulu:")
                        err("  CREATE TABLE IF NOT EXISTS cookies (akun TEXT PRIMARY KEY, paket TEXT, cookie TEXT, ts INTEGER);")
                        kirim_gagal = kirim_gagal + 1
                        break
                    else
                        kirim_gagal = kirim_gagal + 1
                    end
                end
            end
            if kirim_ok > 0 then ok("Kekirim ke panel: " .. kirim_ok .. " cookie -> buka tab Cookie di panel (password)") end
            if kirim_gagal > 0 then warn("Gagal kirim " .. kirim_gagal .. " (cek koneksi / endpoint /cookie-simpan udah dideploy?)") end
        else
            err("Gagal nulis " .. OUT .. " (izin /sdcard? jalanin: termux-setup-storage)")
        end
    else
        warn("Gak ada cookie keambil.")
    end
    return
end

-- ============================================================
-- v5.28: `velium verif` -- DAFTAR CLIENT YANG BUTUH DICEK MANUAL.
--
-- KENAPA BUKAN "DETEKSI CAPTCHA": di RF ini layar Roblox GAK BISA DIBACA
-- (5.9 / v4.85 -- game, layar key, Home, loading semuanya kebaca 0 teks).
-- Jadi mustahil tau "ini lagi nampilin captcha" dari layar. Yang bisa cuma
-- kenali POLA: proses idup tapi bridge gak pernah lapor = nyangkut sebelum
-- masuk game. Verif bot, layar key, popup umur, semuanya masuk pola itu.
-- Command ini nyaring daftarnya, keputusan (ganti akun / verif manual) di lo.
-- ============================================================
if PERINTAH == "captcha" then
    -- v6.53: CEK CAPTCHA ringkas -- fokus WebView aja (bukan 5 bagian ceklayar).
    -- Bawa client ke depan, dump uiautomator, cari penanda captcha. Langsung
    -- kasih tau: KENA atau ENGGAK. `velium captcha seiyx` (+ delay opsional).
    local cfg = load_config()
    if not cfg then err("Config belum ada."); return end
    local client = arg and arg[2]
    if not client then
        err("Client mana?  velium captcha <client> [delay]")
        return
    end
    local pkg = client:find("%.") and client or ("com.roblox." .. client)
    local delay = tonumber(arg and arg[3]) or 0

    if delay > 0 then
        info("Tunggu " .. delay .. "s (siapin client)...")
        sh_silent("su -c 'monkey -p " .. pkg .. " -c android.intent.category.LAUNCHER 1 2>/dev/null'")
        os.execute("sleep " .. delay)
    else
        -- bawa ke depan bentar biar uiautomator bisa baca
        sh_silent("su -c 'monkey -p " .. pkg .. " -c android.intent.category.LAUNCHER 1 2>/dev/null'")
        os.execute("sleep 2")
    end

    sh_silent("su -c 'uiautomator dump /sdcard/cap.xml'")
    local ui = sh("su -c 'cat /sdcard/cap.xml 2>/dev/null'") or ""
    sh_silent("su -c 'rm -f /sdcard/cap.xml'")

    local low = ui:lower()
    local kena = ui:find("FunCaptcha", 1, true) or ui:find("arkose", 1, true)
                 or ui:find("challenge-container", 1, true)
                 or low:find("start puzzle", 1, true)
                 or low:find("not a bot", 1, true)
                 or low:find("solve this challenge", 1, true)
                 or low:find("verifying browser", 1, true)
                 or low:find("verifying you", 1, true)

    print("")
    if kena then
        warn(">>> " .. client .. " KENA CAPTCHA (verif bot) <<<")
        info("Solve manual. Worker bakal skip client ini otomatis.")
    elseif not ui:match("%S") then
        info(client .. ": layar gak kebaca (client mungkin gak di depan).")
    else
        ok(client .. ": GAK kena captcha (aman).")
    end
    return
end

if PERINTAH == "ceklayar" or PERINTAH == "cekcaptcha" then
    -- v6.51: DIAGNOSTIK LAYAR umum. Jalanin PAS client lagi di situasi apa aja
    -- (captcha, error Roblox, layar key Delta, popup). Dump window + activity +
    -- SEMUA teks/desc/webview/resource-id -> biar keliatan elemen yang bisa
    -- dideteksi buat auto-handle. Pakai buat kumpulin data tiap situasi.
    local cfg = load_config()
    if not cfg then err("Config belum ada."); return end
    local client = arg and arg[2]
    if not client then
        err("Client mana?  velium ceklayar <client>")
        info("Jalanin PAS client lagi di situasi yang mau dideteksi")
        info("(captcha / error Roblox / layar key Delta / popup).")
        return
    end
    local pkg = client:find("%.") and client or ("com.roblox." .. client)

    -- v6.53: DELAY opsional (argumen ke-3, detik). Bawa client ke depan + tunggu
    -- biar user sempet siapin (captcha butuh client di depan buat uiautomator).
    local delay = tonumber(arg and arg[3]) or 0
    print(C.BOLD .. C.C .. "\n=== DIAGNOSTIK LAYAR: " .. pkg .. " ===\n" .. C.N)
    if delay > 0 then
        info("Bawa " .. client .. " ke depan + tunggu " .. delay .. "s...")
        info("(client dibawa ke depan biar captcha kebaca uiautomator)")
        sh_silent("su -c 'monkey -p " .. pkg .. " -c android.intent.category.LAUNCHER 1 2>/dev/null'")
        for i = delay, 1, -1 do
            io.write("\r  tunggu " .. i .. "s ...  "); io.flush()
            os.execute("sleep 1")
        end
        print("")
    end

    info("1. Window yang lagi fokus:")
    print(sh("su -c 'dumpsys window | grep -iE \"mCurrentFocus|mFocusedApp\"'") or "(kosong)")

    info("2. SEMUA window punya client ini:")
    print(sh("su -c 'dumpsys window windows | grep -iE \"Window #|" .. pkg .. "\"'") or "(kosong)")

    info("3. Cari window captcha (Arkose/FunCaptcha/challenge/verif):")
    local capt = sh("su -c 'dumpsys window | grep -iE \"arkose|funcaptcha|captcha|challenge|verif|hcaptcha|recaptcha\"'") or ""
    if capt:match("%S") then
        warn("KETEMU window captcha:")
        print(capt)
    else
        info("  (gak ada nama captcha di window -- mungkin di dalam WebView)")
    end

    info("4. Activity stack Roblox:")
    print(sh("su -c 'dumpsys activity activities | grep -iE \"" .. pkg .. "|ResumedActivity\" | head -10'") or "(kosong)")

    info("5. WebView/view yang lagi kebuka (uiautomator):")
    sh_silent("su -c 'uiautomator dump /sdcard/capt.xml'")
    local ui = sh("su -c 'cat /sdcard/capt.xml 2>/dev/null'") or ""
    sh_silent("su -c 'rm -f /sdcard/capt.xml'")
    if ui:match("%S") then
        info("  UI kebaca (" .. #ui .. " char).")
        -- cari petunjuk captcha
        local found = ui:match("[Cc]aptcha") or ui:match("[Aa]rkose") or ui:match("[Rr]obot")
                      or ui:match("[Vv]erif") or ui:match("[Cc]hallenge") or ui:match("[Pp]uzzle")
        if found then
            warn("  >> KETEMU petunjuk captcha: " .. found)
        else
            info("  (gak ada kata captcha langsung)")
        end
        -- tampilin SEMUA teks non-kosong (biar keliatan tombol/label captcha)
        info("  -- Semua TEXT di layar:")
        local adaTeks = false
        for t in ui:gmatch('text="([^"]+)"') do
            if t:match("%S") then print("     [text] " .. t); adaTeks = true end
        end
        if not adaTeks then print("     (gak ada text -- semua kosong)") end
        -- tampilin content-desc (label aksesibilitas)
        info("  -- Semua CONTENT-DESC:")
        local adaDesc = false
        for d in ui:gmatch('content%-desc="([^"]+)"') do
            if d:match("%S") then print("     [desc] " .. d); adaDesc = true end
        end
        if not adaDesc then print("     (gak ada content-desc)") end
        -- tampilin class WebView / resource-id (elemen web = kemungkinan captcha)
        info("  -- WebView / resource-id:")
        local adaWeb = false
        for c in ui:gmatch('class="(android%.webkit%.[^"]+)"') do
            print("     [class] " .. c); adaWeb = true
        end
        for r in ui:gmatch('resource%-id="([^"]+)"') do
            if r:match("%S") then print("     [id] " .. r); adaWeb = true end
        end
        if not adaWeb then print("     (gak ada WebView/resource-id -- layar native/GL)") end
    else
        warn("  uiautomator balikin KOSONG.")
    end

    info("6. Package yang lagi jalan di client (proses):")
    print(sh("su -c 'ps -A | grep -iE \"arkose|captcha|" .. pkg .. "\"'") or "(kosong)")

    print("")
    ok("Diagnostik selesai. Tempel hasil ini ke Claude biar tau apa yg bisa dideteksi.")
    return
end

if PERINTAH == "verif" or PERINTAH == "cekverif" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin setup dulu."); return end

    local list = split(cfg.pkgs)
    print(C.BOLD .. C.C .. "\n=== CLIENT YANG BUTUH DICEK ===\n" .. C.N)
    info("Ngumpulin data (sekali dumpsys + sekali baca prefs)...")

    -- 1. siapa yang idup -- SEKALI dumpsys buat semua (v4.71)
    local jalan = pkg_running_semua(list) or {}

    -- 2. username semua client dalam SATU panggilan su (inget 5.3: su ~6 detik)
    local nama_pkg = {}
    do
        local bagian = {}
        for _, pkg in ipairs(list) do
            bagian[#bagian+1] = "echo @@" .. pkg .. "; cat /data/data/" .. pkg ..
                                "/shared_prefs/prefs.xml 2>/dev/null | grep -o '<string name=\"username\">[^<]*' | head -1"
        end
        local skrip = table.concat(bagian, "; ")
        local h = io.popen("timeout 60 su -c " .. shq(skrip) .. " 2>/dev/null")
        if h then
            local raw = h:read("*all") or ""; h:close()
            local kini
            for baris in raw:gmatch("[^\n]+") do
                local p = baris:match("^@@(%S+)")
                if p then kini = p
                elseif kini then
                    local u = baris:match('<string name="username">(.*)')
                    if u and u:match("%S") then nama_pkg[kini] = u end
                end
            end
        end
    end

    -- 3. bridge: kapan tiap akun terakhir lapor (sekali GET /stat)
    local stat = api_get(cfg, "/stat") or ""
    local now = os.time()

    local perlu, sehat, mati = {}, 0, 0
    for _, pkg in ipairs(list) do
        local hidup = jalan[pkg]
        local akun = nama_pkg[pkg]
        local ts = akun and bridge_ts(stat, akun) or nil
        local umur = ts and (now - ts) or nil

        if not hidup then
            mati = mati + 1
            perlu[#perlu+1] = { pkg = pkg, akun = akun, kelas = "mati",
                sebab = "proses gak jalan", saran = "dibuka worker (bukan verif)" }
        elseif not ts then
            -- idup tapi BELUM PERNAH lapor = nyangkut sebelum masuk game.
            -- Ini pola paling khas buat verif bot / layar key / popup umur.
            perlu[#perlu+1] = { pkg = pkg, akun = akun, kelas = "curiga",
                sebab = "idup tapi BELUM PERNAH lapor ke bridge",
                saran = "CEK LAYARNYA -- kemungkinan verif bot / layar key / popup umur" }
        elseif umur > 900 then
            perlu[#perlu+1] = { pkg = pkg, akun = akun, kelas = "curiga",
                sebab = ("lapor terakhir %d menit lalu"):format(math.floor(umur/60)),
                saran = "CEK LAYARNYA -- keluar game & gak balik, bisa kena verif pas rejoin" }
        elseif umur > 300 then
            perlu[#perlu+1] = { pkg = pkg, akun = akun, kelas = "pantau",
                sebab = ("lapor terakhir %d menit lalu"):format(math.floor(umur/60)),
                saran = "belum tentu masalah -- pantau dulu" }
        else
            sehat = sehat + 1
        end
    end

    print("")
    local nCuriga = 0
    for _, x in ipairs(perlu) do if x.kelas == "curiga" then nCuriga = nCuriga + 1 end end

    if nCuriga > 0 then
        print(C.BOLD .. C.Y .. "  PERLU DILIHAT (" .. nCuriga .. ")" .. C.N)
        for _, x in ipairs(perlu) do
            if x.kelas == "curiga" then
                print("  " .. C.BOLD .. x.pkg .. C.N .. "  " .. C.C .. (x.akun or "?") .. C.N)
                print("     " .. C.Y .. x.sebab .. C.N)
                print("     " .. C.D .. x.saran .. C.N)
            end
        end
        print("")
    end

    local nPantau = 0
    for _, x in ipairs(perlu) do if x.kelas == "pantau" then nPantau = nPantau + 1 end end
    if nPantau > 0 then
        print(C.D .. "  pantau dulu (" .. nPantau .. "):" .. C.N)
        for _, x in ipairs(perlu) do
            if x.kelas == "pantau" then
                print("     " .. x.pkg .. "  " .. (x.akun or "?") .. "  -- " .. C.D .. x.sebab .. C.N)
            end
        end
        print("")
    end

    if mati > 0 then
        print(C.D .. "  gak jalan (" .. mati .. "): " .. C.N)
        for _, x in ipairs(perlu) do
            if x.kelas == "mati" then
                print("     " .. C.D .. x.pkg .. "  " .. (x.akun or "?") .. C.N)
            end
        end
        print("")
    end

    print(C.G .. "  sehat: " .. sehat .. C.N .. C.D .. " (lapor < 5 menit lalu)" .. C.N)
    print("")
    if nCuriga > 0 then
        info("Buat liat layarnya: bawa client ke depan, terus liat sendiri di RF.")
        info("Kalau emang kena verif bot -> verif manual, atau ganti akunnya.")
    else
        ok("Gak ada yang mencurigakan.")
    end
    print("")
    print(C.D .. "  Catatan: worker GAK BISA baca layar di RF ini (lihat 5.9), jadi ini" .. C.N)
    print(C.D .. "  tebakan dari POLA, bukan bacaan captcha. Keputusan tetap di lo." .. C.N)
    return
end

-- ============================================================
-- v5.30: `velium panel` -- UJI SAMBUNGAN KE PANEL, endpoint per endpoint.
--
-- Perlu karena gejalanya menyesatkan: worker keliatan jalan normal (config
-- kebaca, tim kedeteksi, polling jalan) tapi di panel timnya KOSONG. Itu
-- kejadian kalau GET /perintah lolos sementara POST /tim ditolak -- dan dulu
-- hasil POST-nya dibuang, jadi gak ada tanda apa pun.
-- Di sini tiap endpoint dites sendiri dan jawaban mentahnya ditampilin.
-- ============================================================
if PERINTAH == "panel" or PERINTAH == "uji" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin setup dulu."); return end

    print(C.BOLD .. C.C .. "\n=== UJI SAMBUNGAN PANEL ===\n" .. C.N)
    info("URL  : " .. tostring(cfg.url))
    info("tim  : " .. tostring(cfg.tim))
    info("kunci: " .. (cfg.kunci and (cfg.kunci:sub(1, 6) .. "..." .. cfg.kunci:sub(-4)) or "KOSONG"))
    print("")

    local function potong(t, n)
        t = tostring(t or ""):gsub("%s+", " ")
        if #t > (n or 150) then return t:sub(1, n or 150) .. "..." end
        return t
    end

    -- 1. GET /perintah -- ini yang biasanya lolos
    io.write(C.BOLD .. "1. GET /perintah" .. C.N .. "  ")
    local r1 = api_get(cfg, "/perintah?tim=" .. cfg.tim) or ""
    if r1 == "" then
        print(C.R .. "GAK NYAMBUNG" .. C.N)
        err("   URL salah / internet mati / Cloudflare gak balesin")
    else
        local e1 = ambil_str(r1, "error")
        if e1 then print(C.R .. "DITOLAK: " .. e1 .. C.N)
        else print(C.G .. "OK" .. C.N .. "  " .. C.D .. potong(r1) .. C.N) end
    end

    -- 2. POST /tim -- INI yang nentuin tim muncul di panel apa nggak
    io.write(C.BOLD .. "2. POST /tim" .. C.N .. "     ")
    local body = string.format(
        '{"tim":%s,"cpu":0,"ram_used":0,"ram_free":0,"ram_total":0,' ..
        '"jalan":0,"total":0,"sticky":false,"sig":"","clients":[],' ..
        '"aksi":%s,"log":[],"ver":%s,"dev":%s}',
        jstr(cfg.tim), jstr("uji sambungan"), jstr(VERSION), jstr(dev_id()))
    local r2 = api_post(cfg, "/tim", body) or ""
    if r2 == "" then
        print(C.R .. "GAK NYAMBUNG" .. C.N)
    else
        local e2 = ambil_str(r2, "error")
        if e2 then
            print(C.R .. "DITOLAK: " .. e2 .. C.N)
            err("   INI SEBABNYA tim kosong di panel.")
            if e2:find("kunci") then
                err("   Kunci di config beda sama `wrangler secret put KUNCI`.")
            elseif e2:find("jalur") then
                err("   Backend Cloudflare belum di-deploy / versinya lama.")
            elseif e2:find("kosong") then
                err("   Nama tim kosong di config. Setup ulang.")
            end
        else
            print(C.G .. "OK" .. C.N .. "  " .. C.D .. potong(r2) .. C.N)
        end
    end

    -- 3. GET /stat -- cek tim ini BENERAN kecatat
    io.write(C.BOLD .. "3. GET /stat" .. C.N .. "     ")
    local r3 = api_get(cfg, "/stat") or ""
    if r3 == "" then
        print(C.R .. "GAK NYAMBUNG" .. C.N)
    else
        local e3 = ambil_str(r3, "error")
        if e3 then print(C.R .. "DITOLAK: " .. e3 .. C.N)
        else
            -- cari nama tim ini di jawaban
            local ada = r3:find('"nama"%s*:%s*"' .. cfg.tim:gsub("%-", "%%-") .. '"') ~= nil
            if ada then
                print(C.G .. "OK" .. C.N .. "  " .. cfg.tim .. " KECATAT di panel")
            else
                print(C.Y .. "OK tapi " .. cfg.tim .. " GAK ADA di daftar" .. C.N)
                warn("   Panel nerima permintaan, tapi tim ini belum kecatat.")
                warn("   Kalau langkah 2 OK, tunggu ~15 detik terus ulangi.")
            end
        end
    end

    -- 4. klaim tim -- 1 tim = 1 device
    io.write(C.BOLD .. "4. klaim tim" .. C.N .. "     ")
    local r4 = api_get(cfg, "/tim-klaim?tim=" .. cfg.tim .. "&dev=" .. dev_id()) or ""
    if r4 == "" then
        print(C.D .. "gak kebaca (gak fatal)" .. C.N)
    else
        local boleh = ambil_str(r4, "boleh")
        local sebab = ambil_str(r4, "sebab")
        if boleh == "ya" then
            print(C.G .. "OK" .. C.N .. "  tim ini punya kita")
        else
            print(C.R .. "DIPEGANG DEVICE LAIN" .. C.N)
            err("   " .. tostring(sebab or "?"))
            err("   Pakai nomor tim lain, atau tunggu klaim lamanya basi (15 menit).")
        end
    end

    -- 5. akun: apa yang worker TAU vs apa yang panel PUNYA
    -- Ini yang nentuin kenapa panel bisa bilang "0 akun" padahal client-nya ada.
    print("")
    io.write(C.BOLD .. "5. akun yang worker tau" .. C.N .. "  ")
    local mapA = {}
    do
        local pkgs = split(cfg.pkgs)
        local perintah = {}
        for _, pkg in ipairs(pkgs) do
            perintah[#perintah+1] = string.format(
                'echo "@@%s"; cat /data/data/%s/shared_prefs/prefs.xml 2>/dev/null', pkg, pkg)
        end
        local o = sh("su -c '" .. table.concat(perintah, "; ") .. "'") or ""
        local kini
        for baris in o:gmatch("[^\r\n]+") do
            local t = baris:match("^@@(%S+)")
            if t then kini = t
            elseif kini then
                local u = baris:match('<string name="username">(.-)</string>')
                if u then mapA[kini] = u; kini = nil end
            end
        end
        local n = 0
        for _ in pairs(mapA) do n = n + 1 end
        print(n .. " dari " .. #pkgs .. " client")
        for _, pkg in ipairs(pkgs) do
            print("     " .. C.D .. pkg:gsub("com%.roblox%.", "") .. C.N .. "  " ..
                  (mapA[pkg] and (C.C .. mapA[pkg] .. C.N)
                   or (C.Y .. "prefs.xml gak kebaca (client belum pernah login?)" .. C.N)))
        end
    end

    -- 6. daftarin akun itu ke tim (assign-tim), tampilin jawabannya
    io.write(C.BOLD .. "6. POST /assign-tim" .. C.N .. "  ")
    do
        local daftar = {}
        for _, ak in pairs(mapA) do daftar[#daftar+1] = '"' .. ak .. '"' end
        if #daftar == 0 then
            print(C.Y .. "DILEWAT -- gak ada akun yang kebaca" .. C.N)
            err("   Ini sebabnya panel bilang 0 akun: worker sendiri gak tau akunnya.")
            err("   Buka tiap client sekali & login, biar prefs.xml kebentuk.")
        else
            local body = '{"tim":"' .. cfg.tim .. '","game":"' .. (cfg.game_label or "") ..
                         '","isi_kosong":true,"akun":[' .. table.concat(daftar, ",") .. "]}"
            local r6 = api_post(cfg, "/assign-tim", body) or ""
            local e6 = ambil_str(r6, "error")
            if r6 == "" then print(C.R .. "GAK NYAMBUNG" .. C.N)
            elseif e6 then print(C.R .. "DITOLAK: " .. e6 .. C.N)
            else print(C.G .. "OK" .. C.N .. "  " .. C.D .. potong(r6) .. C.N) end
        end
    end

    -- 7. cek di /stat: akun itu kecatat di tim mana & game apa
    io.write(C.BOLD .. "7. cek di /stat" .. C.N .. "      ")
    do
        local r7 = api_get(cfg, "/stat") or ""
        if r7 == "" then
            print(C.R .. "GAK NYAMBUNG" .. C.N)
        else
            print("")
            for _, ak in pairs(mapA) do
                -- cari blok akun ini, ambil tim & game-nya
                local pola = '"nama"%s*:%s*"' .. ak:gsub("([%.%-%+%*%?%[%]%^%$%(%)%%])", "%%%1") .. '"(.-)}'
                local blok = r7:match(pola)
                if blok then
                    local tim = blok:match('"tim"%s*:%s*"(.-)"') or "(kosong)"
                    local game = blok:match('"game"%s*:%s*"(.-)"') or "(kosong)"
                    local cocok = (tim == cfg.tim)
                    print("     " .. (cocok and C.G or C.Y) .. ak .. C.N ..
                          "  tim=" .. tim .. "  game=" .. game ..
                          (cocok and "" or (C.Y .. "  <- BEDA dari " .. cfg.tim .. C.N)))
                else
                    print("     " .. C.R .. ak .. C.N .. "  GAK ADA di panel")
                end
            end
            print("     " .. C.D .. "tim harus = " .. cfg.tim ..
                  " dan game harus = " .. (cfg.game_label or "?") ..
                  " biar nongol di tab itu" .. C.N)
        end
    end

    print("")
    print(C.D .. "  Kalau langkah 2 DITOLAK -> itu akar masalahnya." .. C.N)
    print(C.D .. "  Kalau semua OK tapi panel masih kosong -> panel-nya yang" .. C.N)
    print(C.D .. "  belum di-refresh, atau tab-nya nyaring game yang beda." .. C.N)
    print("")
    return
end

-- ============================================================
-- v5.35: `velium script` -- ganti script autoexec tanpa setup ulang.
-- Tanpa ini, mau tuker STAR FARM <-> STAR SEED harus ngulang setup dari nol
-- (nomor tim, game, scan paket, dst) -- padahal yang mau diubah satu baris.
-- ============================================================
if PERINTAH == "script" or PERINTAH == "sc" then
    local cfg = load_config()
    if not cfg then err("Config belum ada. Jalanin setup dulu."); return end

    local GH = "https://raw.githubusercontent.com/alzafabocahbocah-boop/ronihub/main/"
    local PILIHAN = {
        { "STAR FARM", "gag2",   "farm kebun: tanam, collect, jual" },
        { "STAR SEED", "seed",   "AFK beli seed + gear + pet, terima gift" },
        { "MARKET",    "market", "akun market / TradeWorld" },
    }

    print(C.BOLD .. C.C .. "\n=== GANTI SCRIPT AUTOEXEC ===\n" .. C.N)
    info("tim      : " .. tostring(cfg.tim))
    info("game     : " .. tostring(cfg.game_label or "-"))
    info("sekarang : " .. tostring(cfg.script_label or "-") ..
         "  (" .. tostring(cfg.script_url or "-") .. ")")
    print("")

    -- boleh langsung: velium script seed
    local minta = (arg[2] or ""):lower()
    local sc
    if minta ~= "" then
        for _, x in ipairs(PILIHAN) do
            if minta == x[2] or minta == x[1]:lower():gsub("%s", "")
               or minta == x[1]:lower() then sc = x break end
        end
        if not sc then
            err("'" .. minta .. "' gak dikenal. Pilihannya: gag2 / seed / market")
            return
        end
    else
        for i, x in ipairs(PILIHAN) do
            print(C.D .. string.format("  %d) %-10s -> %-7s  %s", i, x[1], x[2], x[3]) .. C.N)
        end
        print("")
        local ps = ask("Pilih (1/2/3, Enter=batal)", "")
        if ps == "" then info("Dibatalin."); return end
        sc = PILIHAN[tonumber(ps) or 0]
        if not sc then err("Pilihan gak ada."); return end
    end

    if cfg.script_url == (GH .. sc[2]) then
        info("Udah pakai " .. sc[1] .. " -- gak ada yang diubah.")
        return
    end

    cfg.script_url = GH .. sc[2]
    cfg.script_label = sc[1]
    save_config(cfg)
    ok("Config disimpen: " .. sc[1] .. " -> " .. cfg.script_url)

    -- tulis ulang autoexec biar langsung kepakai
    if tulis_autoexec(cfg) then
        print("")
        warn("Client yang LAGI JALAN masih pakai script LAMA.")
        warn("Delta cuma baca autoexec pas masuk game -- jadi harus join ulang:")
        info("  panel -> tim ini -> Rejoin   (atau: velium stop terus jalanin lagi)")
    end
    print("")
    return
end

-- ============================================================
-- v5.53: `velium layar <client>` -- CARI SINYAL "di Home vs di game".
--
-- Latar: worker gak bisa bedain client yang lagi di halaman awal Roblox dari
-- yang udah di dalam game. Akibatnya sapuan tombol key mulai kecepetan.
-- Dugaan awal gua "gak mungkin dibedain" itu SALAH -- panel lain bisa, jadi
-- sinyalnya ada, cuma belum ketemu.
--
-- Alat ini nge-dump SEMUA kandidat sinyal sekaligus. Cara pakainya:
--   1. jalanin pas client lagi di HALAMAN AWAL   -> simpen hasilnya
--   2. jalanin lagi pas client UDAH DI GAME      -> bandingin
-- Yang BEDA di antara dua itu = sinyal yang dicari.
-- ============================================================
-- ============================================================
-- v5.54: `velium layar [client]` -- CARI SINYAL "di Home vs di game",
-- dengan ngukur DUA KALI sendiri terus nunjukin BEDANYA.
--
-- Latar: worker gak bisa bedain client yang lagi di halaman awal Roblox dari
-- yang udah di dalam game -- akibatnya sapuan tombol key mulai kecepetan.
-- Dugaan awal gua "gak mungkin dibedain" itu SALAH: panel lain bisa, jadi
-- sinyalnya ada, cuma belum ketemu.
--
-- Kenapa ngukur sendiri 2x + nge-diff, bukan nyuruh user jalanin 2x:
-- dump mentahnya panjang (9 bagian x belasan baris). Yang dibutuhin cuma
-- BARIS YANG BERUBAH. Jadi alat ini yang ngerjain pembandingannya.
--
-- Alur: hitung mundur -> ukur keadaan 1 -> hitung mundur (user pindahin
-- client) -> ukur keadaan 2 -> tampilin cuma yang beda.
-- ============================================================
if PERINTAH == "layar" then
    local cfg = load_config()
    if not cfg then err("Config belum ada."); return end

    local pkgs = split(cfg.pkgs)
    local target = arg[2]
    if target and not target:find("^com%.") then target = "com.roblox." .. target end
    if not target then
        local potret = pkg_running_semua(pkgs)
        for _, p in ipairs(pkgs) do if potret[p] then target = p break end end
        target = target or pkgs[1]
    end
    if not target then err("Gak ada client di config."); return end

    -- ============================================================
    -- v5.55: TUNJUKIN CLIENT-NYA YANG MANA.
    -- Jendela di RF judulnya "NO MERCY DELTA LITE [64 BIT] 02/03" -- gak ada
    -- nama paketnya. Jadi user gak tau "clienu" itu jendela yang mana, dan
    -- gak bisa ngarahin keadaan yang bener.
    -- Di sini: daftar semua client + nama akunnya, terus yang jadi target
    -- DIBAWA KE DEPAN biar keliatan jelas.
    -- ============================================================
    do
        print("")
        print(C.BOLD .. "  Client di RF ini:" .. C.N)
        local potretL = pkg_running_semua(pkgs)
        for _, p in ipairs(pkgs) do
            local ak = baca_username(p) or "(belum login)"
            local tanda = (p == target) and (C.G .. "  <<< TARGET" .. C.N) or ""
            print(("   %s %-10s %-20s %s%s"):format(
                potretL[p] and (C.G .. "*" .. C.N) or " ",
                p:gsub("com%.roblox%.", ""), ak,
                potretL[p] and "jalan" or "mati", tanda))
        end
        print(C.D .. "   (* = lagi jalan.  ganti target:  velium layar clienv)" .. C.N)

        if potretL[target] then
            info("Bawa " .. target:gsub("com%.roblox%.", "") ..
                 " ke depan biar keliatan yang mana...")
            local url = build_url(cfg, nil)
            sh_silent("su -c \"am start -f 0x20000000 -a android.intent.action.VIEW -d '" ..
                      url .. "' -p " .. target .. "\"")
            os.execute("sleep 2")
            ok("Jendela yang paling depan sekarang = " .. target:gsub("com%.roblox%.", "") ..
               "  (akun " .. (baca_username(target) or "?") .. ")")
        else
            warn(target:gsub("com%.roblox%.", "") .. " GAK JALAN -- gak bisa dibawa ke depan.")
            warn("  Buka dulu client-nya, atau pilih yang lagi jalan (tanda * di atas).")
        end
    end

    -- daftar kandidat sinyal. Tiap entri: { judul, perintah shell }
    local KANDIDAT = {
        { "activity + state",
          "dumpsys activity activities | grep -i " .. target ..
          " | grep -oE '(ActivityRecord\\{[^ ]*|state=[A-Za-z]+|mResumed=[a-z]+|visible=[a-z]+)'" },
        { "window milik client",
          "dumpsys window windows | grep -i " .. target .. " | grep -oE 'Window\\{[^ ]*|mHasSurface=[a-z]+'" },
        { "fokus layar",
          "dumpsys window | grep -iE 'mCurrentFocus|mFocusedApp' | sed 's/  */ /g'" },
        { "jumlah koneksi UDP",
          "cat /proc/net/udp 2>/dev/null | awk 'NR>1 && $5!=\"00000000:0000\"' | wc -l" },
        { "koneksi UDP (alamat tujuan)",
          "cat /proc/net/udp 2>/dev/null | awk 'NR>1 && $5!=\"00000000:0000\" {print $5}' | sort | head -8" },
        { "jumlah koneksi TCP nyambung",
          "cat /proc/net/tcp 2>/dev/null | awk 'NR>1 && $4==\"01\"' | wc -l" },
        { "berkas log Roblox terbaru",
          "for d in /sdcard/Android/data/" .. target .. "/files /data/data/" .. target .. "/files; do " ..
          "ls -t $d/*log* $d/logs/* 2>/dev/null | head -2; done" },
        { "kata kunci di log (join/connect/teleport)",
          "for d in /sdcard/Android/data/" .. target .. "/files /data/data/" .. target .. "/files; do " ..
          "f=$(ls -t $d/*log* $d/logs/* 2>/dev/null | head -1); " ..
          "[ -n \"$f\" ] && tail -80 \"$f\" | grep -oiE '(join[a-z]*|connect[a-z]*|teleport[a-z]*|" ..
          "datamodel|placeid|gameid|serverid)' | sort | uniq -c | head -10; done" },
        { "memori (TOTAL / Graphics)",
          "dumpsys meminfo " .. target .. " 2>/dev/null | grep -iE 'TOTAL PSS|Graphics' | sed 's/  */ /g'" },
    }

    local function ukur()
        local hasil = {}
        for _, k in ipairs(KANDIDAT) do
            local o = sh("su -c " .. shq(k[2])) or ""
            local baris = {}
            for b in o:gmatch("[^\r\n]+") do
                b = b:gsub("^%s+", ""):gsub("%s+$", "")
                if b ~= "" then baris[#baris+1] = b:sub(1, 130) end
            end
            hasil[k[1]] = baris
        end
        return hasil
    end

    -- v5.56: TUNGGU ENTER, bukan hitung mundur.
    -- Hitung mundur 20 detik itu kependekan: user masih harus nyari jendelanya,
    -- tap "Tap anywhere to play", terus nungguin game-nya kebuka. Dan waktu yang
    -- pas itu beda-beda -- tergantung RF lagi berat apa nggak.
    -- Enter = gak ada batas waktu, dan yang megang kendali user.
    local function tungguSiap(pesan, rinci)
        print("")
        print(C.BOLD .. C.Y .. "  " .. pesan .. C.N)
        if rinci then
            for _, r in ipairs(rinci) do print(C.D .. "    " .. r .. C.N) end
        end
        ask("  Tekan ENTER kalau udah siap", "")
        info("  ngukur...")
    end

    print(C.BOLD .. C.C .. "\n=== SINYAL LAYAR: " .. target .. " ===" .. C.N)
    print(C.D .. "  Diukur 2x, terus ditampilin cuma yang BEDA." .. C.N)

    tungguSiap("KEADAAN 1 -- biarin client di HALAMAN AWAL Roblox", {
        "yang keliatan: Search / Charts / Avatar",
        "kalau lagi di dalam game, keluar dulu ke halaman awal",
    })
    local a = ukur()
    ok("Keadaan 1 kerekam.")

    tungguSiap("KEADAAN 2 -- sekarang MASUKIN client ke GAME", {
        "tap 'Tap anywhere to play', tungguin sampai kebun-nya kebuka",
        "gak usah buru-buru -- gak ada batas waktu",
    })
    local b = ukur()
    ok("Keadaan 2 kerekam.")

    -- bandingin
    print("")
    print(C.BOLD .. "=== YANG BEDA (ini sinyal yang dicari) ===" .. C.N)
    local adaBeda = false
    for _, k in ipairs(KANDIDAT) do
        local judul = k[1]
        local la, lb = a[judul] or {}, b[judul] or {}
        local setA, setB = {}, {}
        for _, x in ipairs(la) do setA[x] = true end
        for _, x in ipairs(lb) do setB[x] = true end
        local cumaA, cumaB = {}, {}
        for _, x in ipairs(la) do if not setB[x] then cumaA[#cumaA+1] = x end end
        for _, x in ipairs(lb) do if not setA[x] then cumaB[#cumaB+1] = x end end
        if #cumaA > 0 or #cumaB > 0 then
            adaBeda = true
            print("")
            print(C.BOLD .. "  [" .. judul .. "]" .. C.N)
            for i, x in ipairs(cumaA) do
                if i > 6 then print(C.D .. "      ... (dipotong)" .. C.N) break end
                print(C.Y .. "    - HOME  : " .. x .. C.N)
            end
            for i, x in ipairs(cumaB) do
                if i > 6 then print(C.D .. "      ... (dipotong)" .. C.N) break end
                print(C.G .. "    + GAME  : " .. x .. C.N)
            end
        end
    end
    if not adaBeda then
        warn("  GAK ADA yang beda sama sekali.")
        warn("  Kemungkinan client-nya gak kepindah keadaan, atau sinyalnya di")
        warn("  tempat lain. Coba ulangi dan pastiin keadaan 2 beneran di game.")
    end

    print("")
    print(C.D .. "  Tempel bagian 'YANG BEDA' ini -- itu udah cukup." .. C.N)
    print("")
    return
end

if PERINTAH ~= "" then
    err("Perintah '" .. PERINTAH .. "' gak dikenal di v" .. VERSION)
    print()
    info("Yang ada:")
    info("   velium                    -> jalanin worker")
    info("   velium stop               -> berhenti baik-baik")
    info("   velium status             -> jalan apa nggak")
    info("   velium cek                -> diagnosa deteksi client")
    info("   velium intip <client> [d] -> potret teks di layar client")
    info("   velium lisensi            -> keadaan kunci Delta")
    info("   velium set <cl> <jumlah>  -> cuma atur ukuran jendela (buat nguji)")
    info("   velium catat <cl> <jumlah>-> set ukuran, LO yang tap, kesimpen otomatis")
    info("   velium uji <client>       -> tembak 6 titik, cek pencetan nyampe apa nggak")
    info("   velium ukur <cl> <jumlah> -> set jendela ke ukuran N client, cari tombolnya")
    info("   velium pasang             -> pasang/atur RF baru (gantiin pasang.sh)")
    info("   velium download [id] [pw] -> unduh & pasang APK client (bisa milih 1-10)")
    info("   velium riwayat            -> pola rejoin & kick (buat diagnosa)")
    info("   velium cari <client>      -> worker cari sendiri tombol key + bypass sekalian")
    info("   velium pantau <client>    -> tiap dipencet, koordinatnya langsung nongol")
    info("   velium rekam <client>     -> rekam sekali, ambil satu koordinat")
    info("   velium tap <cl> <x> <y>   -> pencet titik (pecahan 0..1)")
    info("   velium key                -> bypass key Delta (link dari clipboard)")
    info("   velium key <link>         -> bypass key dari link yang diketik")
    info("   velium key set <APIKEY>   -> isi kunci API bypass.vip")
    info("   velium cookie             -> ekstrak cookie akun sendiri (yg lagi jalan) buat backup")
    info("   velium cookie <huruf>     -> ekstrak dari satu client (mis. velium cookie u)")
    info("   velium cookie all         -> ekstrak dari semua paket kepasang")
    info("   velium verif              -> daftar client yang butuh dicek manual (nyangkut/verif bot)")
    info("   velium panel              -> UJI sambungan ke panel (kalau tim kosong di panel)")
    info("   velium script             -> ganti script autoexec (STAR FARM / STAR SEED / MARKET)")
    info("   velium script seed        -> langsung ke STAR SEED, tanpa nanya")
    info("   velium layar [client]     -> dump sinyal layar (buat bedain Home vs di game)")
    print()
    info("Kalau perintahnya harusnya ada, versi di RF ini ketinggalan -- tarik ulang:")
    info("   curl -fsSL <repo>/velium_worker.lua -o ~/velium_worker.lua")
    return
end

print(C.BOLD..C.C.."Velium Worker v"..VERSION.." (Termux)\n"..C.N)

-- jangan dobel: 2 worker di 1 tim = client dibuka barengan, RAM jebol
pid_lama = baca_pid()
if pid_hidup(pid_lama) then
    err("Udah ada worker jalan (pid " .. pid_lama .. ").")
    info("Matiin dulu:  lua5.4 velium_worker.lua stop")
    return
end
hapus(STOP_FILE)   -- sisa dari sesi sebelumnya

cfg=load_config()

-- v4.2: dijalanin Termux:Boot? Gak ada yang bisa ngetik jawaban wizard.
-- Tanpa penjaga ini, worker nyangkut diem-diem nungguin io.read() selamanya.
NON_INTERAKTIF = (os.getenv("VELIUM_AUTO") == "1")

if not cfg then
    if NON_INTERAKTIF then
        err("Config gak ada, dan lagi mode auto (VELIUM_AUTO=1).")
        err("Wizard butuh diketik. Jalanin manual dulu:")
        err("   lua5.4 velium_worker.lua")
        return
    end
    -- config ntfy lama?
    local lama = io.open("velium_worker_ntfy_config.lua","r")
    if lama then
        lama:close()
        warn("Ketemu config ntfy lama. v4.x pakai Cloudflare Worker, bukan ntfy.")
        warn("Setup ulang â€” siapin URL Worker + kunci.")
    else
        warn("Config kosong - setup dulu")
    end
    cfg=setup_wizard()
elseif NON_INTERAKTIF then
    ok("Config loaded (mode auto â€” langsung jalan)")
else
    ok("Config loaded")
    io.write(C.Y.."Run sekarang? (Y=run / E=edit ulang): "..C.N); io.flush()
    local c=io.read()
    if c=="E" or c=="e" then cfg=setup_wizard() end
end
pid = tulis_pid()
info("pid " .. pid .. " (matiin: lua5.4 velium_worker.lua stop)")

okrun,e=pcall(run,cfg)

-- kalau run() keluar sendiri, bersih() udah dipanggil di dalem.
-- Ini jaring pengaman buat error/Ctrl+C.
if not okrun then
    err("Berhenti: "..tostring(e))
    bersih(cfg, "error")
elseif io.open(PID_FILE, "r") then
    bersih(cfg, "selesai")
end
