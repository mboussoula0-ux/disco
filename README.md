# 8ubah bundle — Kettu fork (renamed + plugins embedded)

يبني **حزمة 8ubah** = Kettu معاد تسميته لـ«8ubah» ومعه بلوقناتك مدمجة، تُحمَّل عبر **BTLoader → Load Custom Bundle**.

## كيف يشتغل (مهم)
`BTLoader.dylib` ما فيه Kettu — هو بس يحمّل ملف `kettu.min.js` من رابط. اسم «Kettu» وصفحة Plugins كلها داخل هالحزمة.
فبدل ما نعدّل الدايلب، نبني **حزمتنا** ونوجّه BTLoader لها.

هذا المشروع **ما ينسخ كود Kettu**. الـworkflow **يستنسخ Kettu الأصلي وقت البناء** ويطبّق فوقه:
1. يضيف بلوقناتك (مجلد `overlay/plugins/`) داخل `src/core/plugins/`.
2. يسجّلها في `getCorePlugins()`.
3. يغيّر نصوص «Kettu» الظاهرة → «8ubah» (في `src/core/i18n/default.json`).
4. يبني `kettu.min.js` بـesbuild.

## خطوات التشغيل (كلها على GitHub — ما تحتاج Node على جهازك)
1. اعمل ريبو جديد عام على GitHub، وارفع محتويات هذا المجلد فيه (`.github/`, `overlay/`, `scripts/`, `README.md`).
2. ادفع (push). **Actions** بيشتغل تلقائياً: يستنسخ Kettu، يطبّق التعديلات، يبني، وينشر `8ubah.min.js` في فرع **dist**.
3. رابط حزمتك بيكون:
   `https://raw.githubusercontent.com/<اسمك>/<الريبو>/dist/8ubah.min.js`
4. في الآيفون: افتح قائمة BTLoader (شاشة الـRecovery حقته) → **Load Custom Bundle** → الصق الرابط → أعد التشغيل.
5. افتح إعدادات ديسكورد → بتلقى **«8ubah»** (بدل Kettu)، وداخل Plugins بتلقى بلوقناتك.

## البلوقنات المدمجة هنا (6 — كلها أصلية، كتبتها من جديد)
| البلوقن | يسوي |
|---|---|
| 8ubah Custom RPC | يحط Rich Presence مخصص على حسابك (اسم/تفاصيل/حالة/نوع/صور/أزرار/وقت) — فيه صفحة إعدادات |
| 8ubah No Blocked | **يُظهر** رسائل المحظورين (يفك تجميعها) |
| 8ubah No Call Idle | يمنع طردك من المكالمة بسبب الخمول |
| 8ubah Relationship Notifier | ينبّهك لو صديق حذفك أو انطردت/تبنّدت من سيرفر أو قروب |
| 8ubah Show Hidden Channels | يُظهر وجود القنوات المخفية (لا محتواها) |
| 8ubah Quests Off | يخفي مهام ديسكورد |

كلها تبدأ **مطفأة** (`preenabled=false`) وتتحكم فيها بالكامل (تشغّل/تطفّي) من صفحة Plugins.

### CustomRPC — كيف تستعمله
افتح صفحة Plugins → 8ubah Custom RPC → أيقونة الإعدادات (المفتاح) → عبّي:
- **App name**: اسم ما يظهر (مطلوب).
- **Details / State**: السطرين تحت الاسم.
- **Type**: Playing / Streaming / Listening / Watching / Competing.
- **App ID**: اختياري — ايدي تطبيق ديسكورد (عشان الصور المسجّلة تحته تطلع).
- **Large/Small image**: اسم أصل مسجّل تحت التطبيق أو رابط صورة.
- **Button 1/2**: نص + رابط (يوتيوب/سبوتيفاي/ساوندكلاود… أي رابط).
- **Show elapsed time**: يبيّن الوقت المنقضي.
ثم فعّل **Enabled**. يتطبّق مباشرة ويبقى شغّال طول ما ديسكورد مفتوح.

## البلوقنات الثانية (الحسابات، Reviews، Server Info، Arabic UI)
لسّا كبلوقنات **تثبّت بالرابط** (ملف 8ubah-plugins). أحوّلها مدمجة بعد ما نتأكد من مساراتها الداخلية على جهازك.

## ⚠️ صريح
- **غير مختبر**: ما أقدر أبني ولا أجرّب حزمة RN هنا. الـworkflow مكتوب بعناية بس أول بناء ممكن يحتاج تعديل بسيط (أسماء وحدات أو مسار default.json لو تغيّر إصدار Kettu).
- لو فشل البناء على Actions: انسخ لي السجل وأصلحه.
- أسماء وحدات ديسكورد (RelationshipStore/PermissionStore/FluxDispatcher) تتأكد منها بأدوات مطوّر 8ubah لو بلوقن ما اشتغل — عدّل سطور `findByProps`/`findByStoreName` بأعلى كل ملف.
- هذا **fork تصونه** مع تحديثات Kettu (الـworkflow يسحب آخر نسخة كل بناء).
