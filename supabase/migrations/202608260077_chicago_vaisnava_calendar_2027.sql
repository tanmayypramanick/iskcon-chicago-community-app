-- The 2027 Chicago calendar published by VaisnavaCalendar.Info, downloaded
-- 2026-08-26. The service states that its files are calculated with the latest
-- ISKCON-approved GCal 11 software written by the GBC Calendar Committee.
-- Source file:
-- https://www.vaisnavacalendar.info/ICS/2027/Chicago%20%5BUnited%20States%20of%20America%5D-a2027-ICS.ics
--
-- Every event_kind below was produced by running the app's own parser,
-- src/features/vaisnavaCalendar/ics.ts, over that file, so a year seeded here
-- and a year a Community Head uploads in the app are classified by the same
-- code. Rows keep the ICS file order, as 2026 does, and descriptions are null
-- because the publisher leaves DESCRIPTION empty on every VEVENT.

insert into public.vaisnava_calendar_publications (
  calendar_year, city, time_zone, source_name, source_url, file_name,
  event_count, published_at, published_by
) values (
  2027,
  'Chicago, Illinois',
  'America/Chicago',
  'VaisnavaCalendar.Info — GCal 11',
  'https://www.vaisnavacalendar.info/ICS/2027/Chicago%20%5BUnited%20States%20of%20America%5D-a2027-ICS.ics',
  'Chicago [United States of America]-a2027-ICS.ics',
  244,
  now(),
  null
)
on conflict (calendar_year) do update set
  city = excluded.city,
  time_zone = excluded.time_zone,
  source_name = excluded.source_name,
  source_url = excluded.source_url,
  file_name = excluded.file_name,
  event_count = excluded.event_count,
  published_at = excluded.published_at;

delete from public.vaisnava_calendar_events where calendar_year = 2027;

insert into public.vaisnava_calendar_events (
  calendar_year, event_date, title, description, event_kind, source_uid, sort_order
) values
  (2027, '2027-01-02', 'Fasting for Saphala Ekadasi', null, 'fasting', '20270102-69351-VAISNAVACALENDAR.INFO', 1),
  (2027, '2027-01-02', 'Sri Devananda Pandita -- Disappearance', null, 'disappearance', '20270102-86497-VAISNAVACALENDAR.INFO', 2),
  (2027, '2027-01-03', 'Break fast after 11:12 (1/4 of tithi) LT', null, 'parana', '20270103-21723-VAISNAVACALENDAR.INFO', 3),
  (2027, '2027-01-04', 'Sri Mahesa Pandita -- Disappearance', null, 'disappearance', '20270104-46343-VAISNAVACALENDAR.INFO', 4),
  (2027, '2027-01-04', 'Sri Uddharana Datta Thakura -- Disappearance', null, 'disappearance', '20270104-42962-VAISNAVACALENDAR.INFO', 5),
  (2027, '2027-01-08', 'Sri Locana Dasa Thakura -- Appearance', null, 'appearance', '20270108-57662-VAISNAVACALENDAR.INFO', 6),
  (2027, '2027-01-10', 'Srila Jiva Gosvami -- Disappearance', null, 'disappearance', '20270110-17383-VAISNAVACALENDAR.INFO', 7),
  (2027, '2027-01-10', 'Sri Jagadisa Pandita -- Disappearance', null, 'disappearance', '20270110-36819-VAISNAVACALENDAR.INFO', 8),
  (2027, '2027-01-14', 'Ganga Sagara Mela', null, 'observance', '20270114-25593-VAISNAVACALENDAR.INFO', 9),
  (2027, '2027-01-18', 'Fasting for Putrada Ekadasi', null, 'fasting', '20270118-70280-VAISNAVACALENDAR.INFO', 10),
  (2027, '2027-01-19', 'Break fast 07:13 (sunrise) - 10:25 (1/3 of daylight) LT', null, 'parana', '20270119-33657-VAISNAVACALENDAR.INFO', 11),
  (2027, '2027-01-19', 'Sri Jagadisa Pandita -- Appearance', null, 'appearance', '20270119-97-VAISNAVACALENDAR.INFO', 12),
  (2027, '2027-01-22', 'Sri Krsna Pusya Abhiseka', null, 'observance', '20270122-73449-VAISNAVACALENDAR.INFO', 13),
  (2027, '2027-01-26', 'Sri Ramacandra Kaviraja -- Disappearance', null, 'disappearance', '20270126-98233-VAISNAVACALENDAR.INFO', 14),
  (2027, '2027-01-26', 'Srila Gopala Bhatta Gosvami -- Appearance', null, 'appearance', '20270126-5022-VAISNAVACALENDAR.INFO', 15),
  (2027, '2027-01-27', 'Sri Jayadeva Gosvami -- Disappearance', null, 'disappearance', '20270127-82984-VAISNAVACALENDAR.INFO', 16),
  (2027, '2027-01-28', 'Sri Locana Dasa Thakura -- Disappearance', null, 'disappearance', '20270128-42326-VAISNAVACALENDAR.INFO', 17),
  (2027, '2027-02-01', 'Fasting for Sat-tila Ekadasi', null, 'fasting', '20270201-50718-VAISNAVACALENDAR.INFO', 18),
  (2027, '2027-02-02', 'Break fast 07:02 (sunrise) - 10:23 (1/3 of daylight) LT', null, 'parana', '20270202-59223-VAISNAVACALENDAR.INFO', 19),
  (2027, '2027-02-11', 'Vasanta Pancami', null, 'observance', '20270211-53369-VAISNAVACALENDAR.INFO', 20),
  (2027, '2027-02-11', 'Srimati Visnupriya Devi -- Appearance', null, 'appearance', '20270211-6608-VAISNAVACALENDAR.INFO', 21),
  (2027, '2027-02-11', 'Srila Visvanatha Cakravarti Thakura -- Disappearance', null, 'disappearance', '20270211-82317-VAISNAVACALENDAR.INFO', 22),
  (2027, '2027-02-11', 'Sri Pundarika Vidyanidhi -- Appearance', null, 'appearance', '20270211-14685-VAISNAVACALENDAR.INFO', 23),
  (2027, '2027-02-11', 'Sri Raghunandana Thakura -- Appearance', null, 'appearance', '20270211-43402-VAISNAVACALENDAR.INFO', 24),
  (2027, '2027-02-11', 'Srila Raghunatha Dasa Gosvami -- Appearance', null, 'appearance', '20270211-66398-VAISNAVACALENDAR.INFO', 25),
  (2027, '2027-02-11', 'Sarasvati Puja', null, 'observance', '20270211-54031-VAISNAVACALENDAR.INFO', 26),
  (2027, '2027-02-13', 'Sri Advaita Acarya -- Appearance', null, 'appearance', '20270213-59481-VAISNAVACALENDAR.INFO', 27),
  (2027, '2027-02-13', '(Fast till noon)', null, 'observance', '20270213-89161-VAISNAVACALENDAR.INFO', 28),
  (2027, '2027-02-14', 'Bhismastami', null, 'observance', '20270214-18839-VAISNAVACALENDAR.INFO', 29),
  (2027, '2027-02-15', 'Sri Madhvacarya -- Disappearance', null, 'disappearance', '20270215-43011-VAISNAVACALENDAR.INFO', 30),
  (2027, '2027-02-16', 'Sri Ramanujacarya -- Disappearance', null, 'disappearance', '20270216-36969-VAISNAVACALENDAR.INFO', 31),
  (2027, '2027-02-17', 'Fasting for Bhaimi Ekadasi', null, 'fasting', '20270217-29353-VAISNAVACALENDAR.INFO', 32),
  (2027, '2027-02-17', 'Varaha Dvadasi: Appearance of Lord Varahadeva', null, 'observance', '20270217-82940-VAISNAVACALENDAR.INFO', 33),
  (2027, '2027-02-17', '(Fasting till noon, with feast tomorrow)', null, 'observance', '20270217-78727-VAISNAVACALENDAR.INFO', 34),
  (2027, '2027-02-17', '(Fast till noon for Sri Nityananda, with feast tomorrow)', null, 'observance', '20270217-13970-VAISNAVACALENDAR.INFO', 35),
  (2027, '2027-02-18', 'Break fast 06:42 (sunrise) - 10:17 (1/3 of daylight) LT', null, 'parana', '20270218-53510-VAISNAVACALENDAR.INFO', 36),
  (2027, '2027-02-18', 'Nityananda Trayodasi: Appearance of Sri Nityananda Prabhu', null, 'observance', '20270218-93795-VAISNAVACALENDAR.INFO', 37),
  (2027, '2027-02-18', '(Fasting is done yesterday, today is feast)', null, 'observance', '20270218-11266-VAISNAVACALENDAR.INFO', 38),
  (2027, '2027-02-20', 'Sri Krsna Madhura Utsava', null, 'observance', '20270220-34072-VAISNAVACALENDAR.INFO', 39),
  (2027, '2027-02-20', 'Srila Narottama Dasa Thakura -- Appearance', null, 'appearance', '20270220-58701-VAISNAVACALENDAR.INFO', 40),
  (2027, '2027-02-25', 'Srila Bhaktisiddhanta Sarasvati Thakura -- Appearance', null, 'appearance', '20270225-77150-VAISNAVACALENDAR.INFO', 41),
  (2027, '2027-02-25', '(Fast till noon)', null, 'observance', '20270225-57343-VAISNAVACALENDAR.INFO', 42),
  (2027, '2027-02-25', 'Sri Purusottama Das Thakura -- Disappearance', null, 'disappearance', '20270225-4634-VAISNAVACALENDAR.INFO', 43),
  (2027, '2027-03-03', 'Fasting for Vijaya Ekadasi', null, 'fasting', '20270303-69846-VAISNAVACALENDAR.INFO', 44),
  (2027, '2027-03-04', 'Break fast 06:20 (sunrise) - 10:08 (1/3 of daylight) LT', null, 'parana', '20270304-91828-VAISNAVACALENDAR.INFO', 45),
  (2027, '2027-03-04', 'Sri Isvara Puri -- Disappearance', null, 'disappearance', '20270304-87269-VAISNAVACALENDAR.INFO', 46),
  (2027, '2027-03-06', 'Siva Ratri', null, 'observance', '20270306-45134-VAISNAVACALENDAR.INFO', 47),
  (2027, '2027-03-08', 'Srila Jagannatha Dasa Babaji -- Disappearance', null, 'disappearance', '20270308-53168-VAISNAVACALENDAR.INFO', 48),
  (2027, '2027-03-08', 'Sri Rasikananda -- Disappearance', null, 'disappearance', '20270308-81302-VAISNAVACALENDAR.INFO', 49),
  (2027, '2027-03-11', 'Sri Purusottama Dasa Thakura -- Appearance', null, 'appearance', '20270311-3855-VAISNAVACALENDAR.INFO', 50),
  (2027, '2027-03-14', 'First day of Daylight Saving Time', null, 'observance', '20270314-45759-VAISNAVACALENDAR.INFO', 51),
  (2027, '2027-03-18', 'Fasting for Amalaki vrata Ekadasi', null, 'fasting', '20270318-45070-VAISNAVACALENDAR.INFO', 52),
  (2027, '2027-03-19', 'Break fast 06:55 (sunrise) - 10:57 (1/3 of daylight) DST', null, 'parana', '20270319-10458-VAISNAVACALENDAR.INFO', 53),
  (2027, '2027-03-19', 'Sri Madhavendra Puri -- Disappearance', null, 'disappearance', '20270319-65722-VAISNAVACALENDAR.INFO', 54),
  (2027, '2027-03-22', 'Gaura Purnima: Appearance of Sri Caitanya Mahaprabhu', null, 'festival', '20270322-77972-VAISNAVACALENDAR.INFO', 55),
  (2027, '2027-03-22', '(Fast till moonrise)', null, 'observance', '20270322-83812-VAISNAVACALENDAR.INFO', 56),
  (2027, '2027-03-23', 'Festival of Jagannatha Misra', null, 'festival', '20270323-15574-VAISNAVACALENDAR.INFO', 57),
  (2027, '2027-03-30', 'Sri Srivasa Pandita -- Appearance', null, 'appearance', '20270330-43404-VAISNAVACALENDAR.INFO', 58),
  (2027, '2027-04-02', 'Fasting for Papamocani Ekadasi', null, 'fasting', '20270402-37843-VAISNAVACALENDAR.INFO', 59),
  (2027, '2027-04-03', 'Break fast 06:30 (sunrise) - 10:46 (1/3 of daylight) DST', null, 'parana', '20270403-61804-VAISNAVACALENDAR.INFO', 60),
  (2027, '2027-04-03', 'Sri Govinda Ghosh -- Disappearance', null, 'disappearance', '20270403-59143-VAISNAVACALENDAR.INFO', 61),
  (2027, '2027-04-11', 'Sri Ramanujacarya -- Appearance', null, 'appearance', '20270411-88686-VAISNAVACALENDAR.INFO', 62),
  (2027, '2027-04-14', 'Rama Navami: Appearance of Lord Sri Ramacandra', null, 'observance', '20270414-33332-VAISNAVACALENDAR.INFO', 63),
  (2027, '2027-04-14', '(Fast till sunset)', null, 'observance', '20270414-69366-VAISNAVACALENDAR.INFO', 64),
  (2027, '2027-04-14', 'Tulasi Jala Dan begins.', null, 'observance', '20270414-33331-VAISNAVACALENDAR.INFO', 65),
  (2027, '2027-04-16', 'Fasting for Kamada Ekadasi', null, 'fasting', '20270416-94535-VAISNAVACALENDAR.INFO', 66),
  (2027, '2027-04-17', 'Break fast 06:07 (sunrise) - 10:36 (1/3 of daylight) DST', null, 'parana', '20270417-88699-VAISNAVACALENDAR.INFO', 67),
  (2027, '2027-04-17', 'Damanakaropana Dvadasi', null, 'observance', '20270417-22423-VAISNAVACALENDAR.INFO', 68),
  (2027, '2027-04-20', 'Sri Balarama Rasayatra', null, 'observance', '20270420-81518-VAISNAVACALENDAR.INFO', 69),
  (2027, '2027-04-20', 'Sri Krsna Vasanta Rasa', null, 'observance', '20270420-24750-VAISNAVACALENDAR.INFO', 70),
  (2027, '2027-04-20', 'Appearance of Radha Kunda, snana dana', null, 'observance', '20270420-93489-VAISNAVACALENDAR.INFO', 71),
  (2027, '2027-04-20', 'Sri Vamsivadana Thakura -- Appearance', null, 'appearance', '20270420-17321-VAISNAVACALENDAR.INFO', 72),
  (2027, '2027-04-20', 'Sri Syamananda Prabhu -- Appearance', null, 'appearance', '20270420-24174-VAISNAVACALENDAR.INFO', 73),
  (2027, '2027-04-27', 'Sri Abhirama Thakura -- Disappearance', null, 'disappearance', '20270427-75813-VAISNAVACALENDAR.INFO', 74),
  (2027, '2027-05-01', 'Srila Vrndavana Dasa Thakura -- Disappearance', null, 'disappearance', '20270501-76012-VAISNAVACALENDAR.INFO', 75),
  (2027, '2027-05-02', 'Fasting for Varuthini Ekadasi', null, 'fasting', '20270502-34834-VAISNAVACALENDAR.INFO', 76),
  (2027, '2027-05-03', 'Break fast 05:44 (sunrise) - 09:36 (end of tithi) DST', null, 'parana', '20270503-58710-VAISNAVACALENDAR.INFO', 77),
  (2027, '2027-05-06', 'Sri Gadadhara Pandita -- Appearance', null, 'appearance', '20270506-76491-VAISNAVACALENDAR.INFO', 78),
  (2027, '2027-05-08', 'Aksaya Trtiya. Candana Yatra starts. (Continues for 21 days)', null, 'observance', '20270508-8252-VAISNAVACALENDAR.INFO', 79),
  (2027, '2027-05-12', 'Jahnu Saptami', null, 'observance', '20270512-86032-VAISNAVACALENDAR.INFO', 80),
  (2027, '2027-05-14', 'Srimati Sita Devi (consort of Lord Sri Rama) -- Appearance', null, 'appearance', '20270514-11359-VAISNAVACALENDAR.INFO', 81),
  (2027, '2027-05-14', 'Sri Madhu Pandita -- Disappearance', null, 'disappearance', '20270514-38436-VAISNAVACALENDAR.INFO', 82),
  (2027, '2027-05-14', 'Srimati Jahnava Devi -- Appearance', null, 'appearance', '20270514-22160-VAISNAVACALENDAR.INFO', 83),
  (2027, '2027-05-14', 'Tulasi Jala Dan ends.', null, 'observance', '20270514-7370-VAISNAVACALENDAR.INFO', 84),
  (2027, '2027-05-16', 'Fasting for Mohini Ekadasi', null, 'fasting', '20270516-18486-VAISNAVACALENDAR.INFO', 85),
  (2027, '2027-05-17', 'Break fast 05:28 (sunrise) - 05:59 (end of tithi) DST', null, 'parana', '20270517-99567-VAISNAVACALENDAR.INFO', 86),
  (2027, '2027-05-17', 'Rukmini Dvadasi', null, 'observance', '20270517-28342-VAISNAVACALENDAR.INFO', 87),
  (2027, '2027-05-18', 'Sri Jayananda Prabhu -- Disappearance', null, 'disappearance', '20270518-37624-VAISNAVACALENDAR.INFO', 88),
  (2027, '2027-05-19', 'Nrsimha Caturdasi: Appearance of Lord Nrsimhadeva', null, 'observance', '20270519-4137-VAISNAVACALENDAR.INFO', 89),
  (2027, '2027-05-19', '(Fast till dusk)', null, 'observance', '20270519-84410-VAISNAVACALENDAR.INFO', 90),
  (2027, '2027-05-20', 'Krsna Phula Dola, Salila Vihara', null, 'observance', '20270520-14343-VAISNAVACALENDAR.INFO', 91),
  (2027, '2027-05-20', 'Sri Sri Radha-Ramana Devaji -- Appearance', null, 'appearance', '20270520-50765-VAISNAVACALENDAR.INFO', 92),
  (2027, '2027-05-20', 'Sri Paramesvari Dasa Thakura -- Disappearance', null, 'disappearance', '20270520-56729-VAISNAVACALENDAR.INFO', 93),
  (2027, '2027-05-20', 'Sri Madhavendra Puri -- Appearance', null, 'appearance', '20270520-76244-VAISNAVACALENDAR.INFO', 94),
  (2027, '2027-05-20', 'Sri Srinivasa Acarya -- Appearance', null, 'appearance', '20270520-68636-VAISNAVACALENDAR.INFO', 95),
  (2027, '2027-05-25', 'Sri Ramananda Raya -- Disappearance', null, 'disappearance', '20270525-46112-VAISNAVACALENDAR.INFO', 96),
  (2027, '2027-05-31', 'Fasting for Apara Ekadasi', null, 'fasting', '20270531-30089-VAISNAVACALENDAR.INFO', 97),
  (2027, '2027-06-01', 'Break fast 05:18 (sunrise) - 10:18 (1/3 of daylight) DST', null, 'parana', '20270601-15866-VAISNAVACALENDAR.INFO', 98),
  (2027, '2027-06-01', 'Srila Vrndavana Dasa Thakura -- Appearance', null, 'appearance', '20270601-30854-VAISNAVACALENDAR.INFO', 99),
  (2027, '2027-06-13', 'Ganga Puja', null, 'observance', '20270613-68839-VAISNAVACALENDAR.INFO', 100),
  (2027, '2027-06-13', 'Sri Baladeva Vidyabhusana -- Disappearance', null, 'disappearance', '20270613-50075-VAISNAVACALENDAR.INFO', 101),
  (2027, '2027-06-13', 'Srimati Gangamata Gosvamini -- Appearance', null, 'appearance', '20270613-23745-VAISNAVACALENDAR.INFO', 102),
  (2027, '2027-06-14', 'Fasting for Pandava Nirjala Ekadasi', null, 'fasting', '20270614-31900-VAISNAVACALENDAR.INFO', 103),
  (2027, '2027-06-15', 'Break fast 05:14 (sunrise) - 10:19 (1/3 of daylight) DST', null, 'parana', '20270615-22885-VAISNAVACALENDAR.INFO', 104),
  (2027, '2027-06-16', 'Panihati Cida Dahi Utsava', null, 'observance', '20270616-77733-VAISNAVACALENDAR.INFO', 105),
  (2027, '2027-06-18', 'Snana Yatra', null, 'observance', '20270618-75255-VAISNAVACALENDAR.INFO', 106),
  (2027, '2027-06-18', 'Sri Mukunda Datta -- Disappearance', null, 'disappearance', '20270618-27815-VAISNAVACALENDAR.INFO', 107),
  (2027, '2027-06-18', 'Sri Sridhara Pandita -- Disappearance', null, 'disappearance', '20270618-56373-VAISNAVACALENDAR.INFO', 108),
  (2027, '2027-06-19', 'Sri Syamananda Prabhu -- Disappearance', null, 'disappearance', '20270619-1550-VAISNAVACALENDAR.INFO', 109),
  (2027, '2027-06-23', 'Sri Vakresvara Pandita -- Appearance', null, 'appearance', '20270623-33552-VAISNAVACALENDAR.INFO', 110),
  (2027, '2027-06-29', 'Sri Srivasa Pandita -- Disappearance', null, 'disappearance', '20270629-87410-VAISNAVACALENDAR.INFO', 111),
  (2027, '2027-06-30', 'Fasting for Yogini Ekadasi', null, 'fasting', '20270630-22604-VAISNAVACALENDAR.INFO', 112),
  (2027, '2027-07-01', 'Break fast 05:19 (sunrise) - 07:46 (end of tithi) DST', null, 'parana', '20270701-25461-VAISNAVACALENDAR.INFO', 113),
  (2027, '2027-07-03', 'Srila Bhaktivinoda Thakura -- Disappearance', null, 'disappearance', '20270703-78461-VAISNAVACALENDAR.INFO', 114),
  (2027, '2027-07-03', '(Fast till noon)', null, 'observance', '20270703-99772-VAISNAVACALENDAR.INFO', 115),
  (2027, '2027-07-03', 'Sri Gadadhara Pandita -- Disappearance', null, 'disappearance', '20270703-12554-VAISNAVACALENDAR.INFO', 116),
  (2027, '2027-07-04', 'Gundica Marjana', null, 'observance', '20270704-14672-VAISNAVACALENDAR.INFO', 117),
  (2027, '2027-07-05', 'Ratha Yatra', null, 'festival', '20270705-31623-VAISNAVACALENDAR.INFO', 118),
  (2027, '2027-07-05', 'Sri Svarupa Damodara Gosvami -- Disappearance', null, 'disappearance', '20270705-78270-VAISNAVACALENDAR.INFO', 119),
  (2027, '2027-07-05', 'Sri Sivananda Sena -- Disappearance', null, 'disappearance', '20270705-96551-VAISNAVACALENDAR.INFO', 120),
  (2027, '2027-07-09', 'Hera Pancami (4 days after Ratha Yatra)', null, 'festival', '20270709-19298-VAISNAVACALENDAR.INFO', 121),
  (2027, '2027-07-09', 'Sri Vakresvara Pandita -- Disappearance', null, 'disappearance', '20270709-13268-VAISNAVACALENDAR.INFO', 122),
  (2027, '2027-07-13', 'Fasting for Sayana Ekadasi', null, 'fasting', '20270713-52242-VAISNAVACALENDAR.INFO', 123),
  (2027, '2027-07-13', 'Return Ratha (8 days after Ratha Yatra)', null, 'festival', '20270713-21473-VAISNAVACALENDAR.INFO', 124),
  (2027, '2027-07-14', 'Break fast 09:04 (1/4 of tithi) - 10:26 (1/3 of daylight) DST', null, 'parana', '20270714-35683-VAISNAVACALENDAR.INFO', 125),
  (2027, '2027-07-18', 'Guru (Vyasa) Purnima', null, 'observance', '20270718-21477-VAISNAVACALENDAR.INFO', 126),
  (2027, '2027-07-18', 'Srila Sanatana Gosvami -- Disappearance', null, 'disappearance', '20270718-26217-VAISNAVACALENDAR.INFO', 127),
  (2027, '2027-07-18', 'First month of Caturmasya begins [PURNIMA SYSTEM]', null, 'observance', '20270718-67609-VAISNAVACALENDAR.INFO', 128),
  (2027, '2027-07-18', '(green leafy vegetable fast for one month)', null, 'observance', '20270718-89026-VAISNAVACALENDAR.INFO', 129),
  (2027, '2027-07-23', 'Srila Gopala Bhatta Gosvami -- Disappearance', null, 'disappearance', '20270723-74153-VAISNAVACALENDAR.INFO', 130),
  (2027, '2027-07-26', 'Srila Lokanatha Gosvami -- Disappearance', null, 'disappearance', '20270726-14660-VAISNAVACALENDAR.INFO', 131),
  (2027, '2027-07-27', 'The incorporation of ISKCON in New York', null, 'observance', '20270727-47329-VAISNAVACALENDAR.INFO', 132),
  (2027, '2027-07-29', 'Fasting for Kamika Ekadasi', null, 'fasting', '20270729-38480-VAISNAVACALENDAR.INFO', 133),
  (2027, '2027-07-30', 'Break fast 05:42 (sunrise) - 10:31 (1/3 of daylight) DST', null, 'parana', '20270730-22164-VAISNAVACALENDAR.INFO', 134),
  (2027, '2027-08-05', 'Sri Vamsidasa Babaji -- Disappearance', null, 'disappearance', '20270805-13394-VAISNAVACALENDAR.INFO', 135),
  (2027, '2027-08-05', 'Sri Raghunandana Thakura -- Disappearance', null, 'disappearance', '20270805-11293-VAISNAVACALENDAR.INFO', 136),
  (2027, '2027-08-12', 'Fasting for Pavitraropana Ekadasi', null, 'fasting', '20270812-59889-VAISNAVACALENDAR.INFO', 137),
  (2027, '2027-08-12', 'Radha Govinda Jhulana Yatra begins', null, 'observance', '20270812-31047-VAISNAVACALENDAR.INFO', 138),
  (2027, '2027-08-13', 'Break fast 05:56 (sunrise) - 10:35 (1/3 of daylight) DST', null, 'parana', '20270813-78100-VAISNAVACALENDAR.INFO', 139),
  (2027, '2027-08-13', 'Srila Rupa Gosvami -- Disappearance', null, 'disappearance', '20270813-41317-VAISNAVACALENDAR.INFO', 140),
  (2027, '2027-08-13', 'Sri Gauridasa Pandita -- Disappearance', null, 'disappearance', '20270813-52278-VAISNAVACALENDAR.INFO', 141),
  (2027, '2027-08-15', 'Last day of the first Caturmasya month [PURNIMA SYSTEM]', null, 'observance', '20270815-41411-VAISNAVACALENDAR.INFO', 142),
  (2027, '2027-08-16', 'Lord Balarama -- Appearance', null, 'appearance', '20270816-46809-VAISNAVACALENDAR.INFO', 143),
  (2027, '2027-08-16', '(Fast till noon)', null, 'observance', '20270816-40640-VAISNAVACALENDAR.INFO', 144),
  (2027, '2027-08-16', 'Jhulana Yatra ends', null, 'observance', '20270816-25397-VAISNAVACALENDAR.INFO', 145),
  (2027, '2027-08-16', 'Second month of Caturmasya begins [PURNIMA SYSTEM]', null, 'observance', '20270816-84470-VAISNAVACALENDAR.INFO', 146),
  (2027, '2027-08-16', '(yogurt fast for one month)', null, 'observance', '20270816-63753-VAISNAVACALENDAR.INFO', 147),
  (2027, '2027-08-17', 'Srila Prabhupada''s departure for the USA', null, 'observance', '20270817-59614-VAISNAVACALENDAR.INFO', 148),
  (2027, '2027-08-25', 'Sri Krsna Janmastami: Appearance of Lord Sri Krsna', null, 'festival', '20270825-48159-VAISNAVACALENDAR.INFO', 149),
  (2027, '2027-08-25', '(Fast till midnight)', null, 'observance', '20270825-30530-VAISNAVACALENDAR.INFO', 150),
  (2027, '2027-08-26', 'Nandotsava', null, 'observance', '20270826-53099-VAISNAVACALENDAR.INFO', 151),
  (2027, '2027-08-26', 'Srila Prabhupada -- Appearance', null, 'appearance', '20270826-9274-VAISNAVACALENDAR.INFO', 152),
  (2027, '2027-08-26', '(Fast till noon)', null, 'observance', '20270826-95674-VAISNAVACALENDAR.INFO', 153),
  (2027, '2027-08-28', 'Fasting for Annada Ekadasi', null, 'fasting', '20270828-42386-VAISNAVACALENDAR.INFO', 154),
  (2027, '2027-08-29', 'Break fast 06:13 (sunrise) - 10:38 (1/3 of daylight) DST', null, 'parana', '20270829-15338-VAISNAVACALENDAR.INFO', 155),
  (2027, '2027-09-04', 'Srimati Sita Thakurani (Sri Advaita''s consort) -- Appearance', null, 'appearance', '20270904-47451-VAISNAVACALENDAR.INFO', 156),
  (2027, '2027-09-07', 'Radhastami: Appearance of Srimati Radharani', null, 'observance', '20270907-7394-VAISNAVACALENDAR.INFO', 157),
  (2027, '2027-09-07', '(Fast till noon)', null, 'observance', '20270907-52178-VAISNAVACALENDAR.INFO', 158),
  (2027, '2027-09-11', 'Fasting for Parsva Ekadasi', null, 'fasting', '20270911-8751-VAISNAVACALENDAR.INFO', 159),
  (2027, '2027-09-11', '(Fast till noon for Vamanadeva, with feast tomorrow)', null, 'observance', '20270911-66572-VAISNAVACALENDAR.INFO', 160),
  (2027, '2027-09-12', 'Break fast 06:27 (sunrise) - 10:40 (1/3 of daylight) DST', null, 'parana', '20270912-25349-VAISNAVACALENDAR.INFO', 161),
  (2027, '2027-09-12', 'Sri Vamana Dvadasi: Appearance of Lord Vamanadeva', null, 'observance', '20270912-65141-VAISNAVACALENDAR.INFO', 162),
  (2027, '2027-09-12', '(Fasting is done yesterday, today is feast)', null, 'observance', '20270912-61457-VAISNAVACALENDAR.INFO', 163),
  (2027, '2027-09-12', 'Srila Jiva Gosvami -- Appearance', null, 'appearance', '20270912-52941-VAISNAVACALENDAR.INFO', 164),
  (2027, '2027-09-13', 'Srila Bhaktivinoda Thakura -- Appearance', null, 'appearance', '20270913-91805-VAISNAVACALENDAR.INFO', 165),
  (2027, '2027-09-13', '(Fast till noon)', null, 'observance', '20270913-54654-VAISNAVACALENDAR.INFO', 166),
  (2027, '2027-09-14', 'Ananta Caturdasi Vrata', null, 'observance', '20270914-84059-VAISNAVACALENDAR.INFO', 167),
  (2027, '2027-09-14', 'Srila Haridasa Thakura -- Disappearance', null, 'disappearance', '20270914-21633-VAISNAVACALENDAR.INFO', 168),
  (2027, '2027-09-14', 'Last day of the second Caturmasya month [PURNIMA SYSTEM]', null, 'observance', '20270914-55147-VAISNAVACALENDAR.INFO', 169),
  (2027, '2027-09-15', 'Sri Visvarupa Mahotsava', null, 'observance', '20270915-63990-VAISNAVACALENDAR.INFO', 170),
  (2027, '2027-09-15', 'Bhadra Purnima', null, 'observance', '20270915-12364-VAISNAVACALENDAR.INFO', 171),
  (2027, '2027-09-15', 'Acceptance of sannyasa by Srila Prabhupada', null, 'observance', '20270915-96163-VAISNAVACALENDAR.INFO', 172),
  (2027, '2027-09-15', 'Third month of Caturmasya begins [PURNIMA SYSTEM]', null, 'observance', '20270915-24388-VAISNAVACALENDAR.INFO', 173),
  (2027, '2027-09-15', '(milk fast for one month)', null, 'observance', '20270915-87129-VAISNAVACALENDAR.INFO', 174),
  (2027, '2027-09-22', 'Srila Prabhupada''s arrival in the USA', null, 'observance', '20270922-67878-VAISNAVACALENDAR.INFO', 175),
  (2027, '2027-09-26', 'Trisprsa Mahadvadasi', null, 'ekadasi', '20270926-98626-VAISNAVACALENDAR.INFO', 176),
  (2027, '2027-09-26', 'Fasting for Indira Ekadasi', null, 'fasting', '20270926-72165-VAISNAVACALENDAR.INFO', 177),
  (2027, '2027-09-27', 'Break fast 06:43 (sunrise) - 10:41 (1/3 of daylight) DST', null, 'parana', '20270927-6060-VAISNAVACALENDAR.INFO', 178),
  (2027, '2027-10-06', 'Durga Puja', null, 'observance', '20271006-39694-VAISNAVACALENDAR.INFO', 179),
  (2027, '2027-10-09', 'Ramacandra Vijayotsava', null, 'observance', '20271009-33916-VAISNAVACALENDAR.INFO', 180),
  (2027, '2027-10-09', 'Sri Madhvacarya -- Appearance', null, 'appearance', '20271009-67083-VAISNAVACALENDAR.INFO', 181),
  (2027, '2027-10-10', 'Fasting for Pasankusa Ekadasi', null, 'fasting', '20271010-9058-VAISNAVACALENDAR.INFO', 182),
  (2027, '2027-10-11', 'Break fast 10:11 (1/4 of tithi) - 10:44 (1/3 of daylight) DST', null, 'parana', '20271011-44623-VAISNAVACALENDAR.INFO', 183),
  (2027, '2027-10-11', 'Srila Raghunatha Dasa Gosvami -- Disappearance', null, 'disappearance', '20271011-95071-VAISNAVACALENDAR.INFO', 184),
  (2027, '2027-10-11', 'Srila Raghunatha Bhatta Gosvami -- Disappearance', null, 'disappearance', '20271011-5230-VAISNAVACALENDAR.INFO', 185),
  (2027, '2027-10-11', 'Srila Krsnadasa Kaviraja Gosvami -- Disappearance', null, 'disappearance', '20271011-73925-VAISNAVACALENDAR.INFO', 186),
  (2027, '2027-10-14', 'Last day of the third Caturmasya month [PURNIMA SYSTEM]', null, 'observance', '20271014-37419-VAISNAVACALENDAR.INFO', 187),
  (2027, '2027-10-15', 'Sri Krsna Saradiya Rasayatra', null, 'observance', '20271015-28670-VAISNAVACALENDAR.INFO', 188),
  (2027, '2027-10-15', 'Sri Murari Gupta -- Disappearance', null, 'disappearance', '20271015-51752-VAISNAVACALENDAR.INFO', 189),
  (2027, '2027-10-15', 'Laksmi Puja', null, 'observance', '20271015-44004-VAISNAVACALENDAR.INFO', 190),
  (2027, '2027-10-15', 'Fourth month of Caturmasya begins [PURNIMA SYSTEM]', null, 'observance', '20271015-14982-VAISNAVACALENDAR.INFO', 191),
  (2027, '2027-10-15', '(urad dal fast for one month)', null, 'observance', '20271015-86788-VAISNAVACALENDAR.INFO', 192),
  (2027, '2027-10-19', 'Srila Narottama Dasa Thakura -- Disappearance', null, 'disappearance', '20271019-23775-VAISNAVACALENDAR.INFO', 193),
  (2027, '2027-10-22', 'Bahulastami', null, 'observance', '20271022-51598-VAISNAVACALENDAR.INFO', 194),
  (2027, '2027-10-23', 'Sri Virabhadra -- Appearance', null, 'appearance', '20271023-77604-VAISNAVACALENDAR.INFO', 195),
  (2027, '2027-10-25', 'Fasting for Rama Ekadasi', null, 'fasting', '20271025-51379-VAISNAVACALENDAR.INFO', 196),
  (2027, '2027-10-26', 'Break fast 07:15 (sunrise) - 10:48 (1/3 of daylight) DST', null, 'parana', '20271026-80353-VAISNAVACALENDAR.INFO', 197),
  (2027, '2027-10-29', 'Dipa dana, Dipavali, (Kali Puja)', null, 'festival', '20271029-3187-VAISNAVACALENDAR.INFO', 198),
  (2027, '2027-10-30', 'Go Puja. Go Krda. Govardhana Puja.', null, 'festival', '20271030-87464-VAISNAVACALENDAR.INFO', 199),
  (2027, '2027-10-30', 'Bali Daityaraja Puja', null, 'observance', '20271030-58440-VAISNAVACALENDAR.INFO', 200),
  (2027, '2027-10-30', 'Sri Rasikananda -- Appearance', null, 'appearance', '20271030-1366-VAISNAVACALENDAR.INFO', 201),
  (2027, '2027-10-31', 'Sri Vasudeva Ghosh -- Disappearance', null, 'disappearance', '20271031-60305-VAISNAVACALENDAR.INFO', 202),
  (2027, '2027-11-01', 'Srila Prabhupada -- Disappearance', null, 'disappearance', '20271101-55535-VAISNAVACALENDAR.INFO', 203),
  (2027, '2027-11-01', '(Fast till noon)', null, 'observance', '20271101-22174-VAISNAVACALENDAR.INFO', 204),
  (2027, '2027-11-06', 'Gopastami, Gosthastami', null, 'observance', '20271106-60730-VAISNAVACALENDAR.INFO', 205),
  (2027, '2027-11-06', 'Sri Gadadhara Dasa Gosvami -- Disappearance', null, 'disappearance', '20271106-57307-VAISNAVACALENDAR.INFO', 206),
  (2027, '2027-11-06', 'Sri Dhananjaya Pandita -- Disappearance', null, 'disappearance', '20271106-19158-VAISNAVACALENDAR.INFO', 207),
  (2027, '2027-11-06', 'Sri Srinivasa Acarya -- Disappearance', null, 'disappearance', '20271106-77034-VAISNAVACALENDAR.INFO', 208),
  (2027, '2027-11-06', 'Last day of Daylight Saving Time', null, 'observance', '20271106-38306-VAISNAVACALENDAR.INFO', 209),
  (2027, '2027-11-07', 'Jagaddhatri Puja', null, 'observance', '20271107-47292-VAISNAVACALENDAR.INFO', 210),
  (2027, '2027-11-09', 'Fasting for Utthana Ekadasi', null, 'fasting', '20271109-65313-VAISNAVACALENDAR.INFO', 211),
  (2027, '2027-11-09', 'Srila Gaura Kisora Dasa Babaji -- Disappearance', null, 'disappearance', '20271109-20393-VAISNAVACALENDAR.INFO', 212),
  (2027, '2027-11-09', '(Fasting till noon, with feast tomorrow)', null, 'observance', '20271109-85605-VAISNAVACALENDAR.INFO', 213),
  (2027, '2027-11-09', 'First day of Bhisma Pancaka', null, 'observance', '20271109-66528-VAISNAVACALENDAR.INFO', 214),
  (2027, '2027-11-10', 'Break fast 06:33 (sunrise) - 09:54 (1/3 of daylight) LT', null, 'parana', '20271110-50991-VAISNAVACALENDAR.INFO', 215),
  (2027, '2027-11-12', 'Sri Bhugarbha Gosvami -- Disappearance', null, 'disappearance', '20271112-67209-VAISNAVACALENDAR.INFO', 216),
  (2027, '2027-11-12', 'Sri Kasisvara Pandita -- Disappearance', null, 'disappearance', '20271112-11656-VAISNAVACALENDAR.INFO', 217),
  (2027, '2027-11-12', 'Last day of the fourth Caturmasya month [PURNIMA SYSTEM]', null, 'observance', '20271112-38733-VAISNAVACALENDAR.INFO', 218),
  (2027, '2027-11-13', 'Sri Krsna Rasayatra', null, 'observance', '20271113-59286-VAISNAVACALENDAR.INFO', 219),
  (2027, '2027-11-13', 'Tulasi-Saligrama Vivaha (marriage)', null, 'observance', '20271113-75938-VAISNAVACALENDAR.INFO', 220),
  (2027, '2027-11-13', 'Sri Nimbarkacarya -- Appearance', null, 'appearance', '20271113-94037-VAISNAVACALENDAR.INFO', 221),
  (2027, '2027-11-13', 'Last day of Bhisma Pancaka', null, 'observance', '20271113-87986-VAISNAVACALENDAR.INFO', 222),
  (2027, '2027-11-14', 'Katyayani vrata begins', null, 'observance', '20271114-65275-VAISNAVACALENDAR.INFO', 223),
  (2027, '2027-11-23', 'Fasting for Utpanna Ekadasi', null, 'fasting', '20271123-91770-VAISNAVACALENDAR.INFO', 224),
  (2027, '2027-11-23', 'Sri Narahari Sarakara Thakura -- Disappearance', null, 'disappearance', '20271123-35585-VAISNAVACALENDAR.INFO', 225),
  (2027, '2027-11-24', 'Break fast 06:50 (sunrise) - 10:01 (1/3 of daylight) LT', null, 'parana', '20271124-3922-VAISNAVACALENDAR.INFO', 226),
  (2027, '2027-11-24', 'Sri Kaliya Krsnadasa -- Disappearance', null, 'disappearance', '20271124-22463-VAISNAVACALENDAR.INFO', 227),
  (2027, '2027-11-25', 'Sri Saranga Thakura -- Disappearance', null, 'disappearance', '20271125-87695-VAISNAVACALENDAR.INFO', 228),
  (2027, '2027-12-03', 'Odana sasthi', null, 'observance', '20271203-77045-VAISNAVACALENDAR.INFO', 229),
  (2027, '2027-12-09', 'Fasting for Moksada Ekadasi', null, 'fasting', '20271209-67784-VAISNAVACALENDAR.INFO', 230),
  (2027, '2027-12-09', 'Advent of Srimad Bhagavad-gita', null, 'observance', '20271209-91492-VAISNAVACALENDAR.INFO', 231),
  (2027, '2027-12-10', 'Break fast 07:07 (sunrise) - 10:11 (1/3 of daylight) LT', null, 'parana', '20271210-88719-VAISNAVACALENDAR.INFO', 232),
  (2027, '2027-12-13', 'Katyayani vrata ends', null, 'observance', '20271213-70125-VAISNAVACALENDAR.INFO', 233),
  (2027, '2027-12-16', 'Srila Bhaktisiddhanta Sarasvati Thakura -- Disappearance', null, 'disappearance', '20271216-42021-VAISNAVACALENDAR.INFO', 234),
  (2027, '2027-12-16', '(Fast till noon)', null, 'observance', '20271216-36534-VAISNAVACALENDAR.INFO', 235),
  (2027, '2027-12-16', '--------- Dhanus Sankranti (Sun enters Sagittarius on 16 Dec, 04:58 LT) ---------', null, 'observance', '20271216-1516-VAISNAVACALENDAR.INFO', 236),
  (2027, '2027-12-23', 'Fasting for Saphala Ekadasi', null, 'fasting', '20271223-2010-VAISNAVACALENDAR.INFO', 237),
  (2027, '2027-12-23', 'Sri Devananda Pandita -- Disappearance', null, 'disappearance', '20271223-90161-VAISNAVACALENDAR.INFO', 238),
  (2027, '2027-12-24', 'Break fast 07:16 (sunrise) - 10:18 (1/3 of daylight) LT', null, 'parana', '20271224-25-VAISNAVACALENDAR.INFO', 239),
  (2027, '2027-12-25', 'Sri Mahesa Pandita -- Disappearance', null, 'disappearance', '20271225-66860-VAISNAVACALENDAR.INFO', 240),
  (2027, '2027-12-25', 'Sri Uddharana Datta Thakura -- Disappearance', null, 'disappearance', '20271225-12193-VAISNAVACALENDAR.INFO', 241),
  (2027, '2027-12-28', 'Sri Locana Dasa Thakura -- Appearance', null, 'appearance', '20271228-94992-VAISNAVACALENDAR.INFO', 242),
  (2027, '2027-12-30', 'Srila Jiva Gosvami -- Disappearance', null, 'disappearance', '20271230-17223-VAISNAVACALENDAR.INFO', 243),
  (2027, '2027-12-30', 'Sri Jagadisa Pandita -- Disappearance', null, 'disappearance', '20271230-20241-VAISNAVACALENDAR.INFO', 244)
;

-- A seed is only worth anything if a bad one refuses to apply. The unique and
-- check constraints already stop duplicate source_uids and unknown kinds; these
-- restate the year, the count and the publication's own event_count so a
-- mis-generated file fails here rather than reaching a devotee's calendar.
do $$
declare
  seeded integer;
  declared integer;
begin
  select count(*) into seeded
  from public.vaisnava_calendar_events
  where calendar_year = 2027;

  if seeded <> 244 then
    raise exception 'The 2027 Chicago calendar seeded % events, expected 244.', seeded;
  end if;

  if exists (
    select 1 from public.vaisnava_calendar_events
    where calendar_year = 2027
      and extract(year from event_date)::integer <> 2027
  ) then
    raise exception 'The 2027 Chicago calendar contains an event outside 2027.';
  end if;

  if exists (
    select 1 from public.vaisnava_calendar_events
    where calendar_year = 2027
      and event_kind not in (
        'ekadasi', 'parana', 'fasting', 'festival',
        'appearance', 'disappearance', 'observance', 'other'
      )
  ) then
    raise exception 'The 2027 Chicago calendar contains an unknown event type.';
  end if;

  select event_count into declared
  from public.vaisnava_calendar_publications
  where calendar_year = 2027;

  if declared is distinct from seeded then
    raise exception 'The 2027 publication says % events but % were seeded.', declared, seeded;
  end if;
end;
$$;
