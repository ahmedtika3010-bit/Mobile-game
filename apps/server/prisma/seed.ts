/**
 * Sample quiz questions so a local build is playable. They are written by the
 * developer and NOT yet reviewed: they are inserted as `in_review` and only
 * become playable after approval in the admin panel. For local testing only,
 * `npm run db:seed -- --approve-for-local-testing` approves them directly.
 */
import { prisma } from '../src/db';

type Q = [category: string, difficulty: string, prompt: string, choices: string[], explanation?: string];

// The first choice is the correct one; choices are shuffled per match.
const QUESTIONS: Q[] = [
  ['geography', 'easy', 'ما عاصمة اليابان؟', ['طوكيو', 'أوساكا', 'كيوتو', 'ناغويا']],
  ['geography', 'easy', 'ما أطول نهر في قارة أفريقيا؟', ['النيل', 'الكونغو', 'النيجر', 'الزامبيزي']],
  ['geography', 'easy', 'ما عاصمة المغرب؟', ['الرباط', 'الدار البيضاء', 'مراكش', 'فاس']],
  ['geography', 'easy', 'ما أكبر محيط في العالم؟', ['المحيط الهادئ', 'المحيط الأطلسي', 'المحيط الهندي', 'المحيط المتجمد الشمالي']],
  ['geography', 'medium', 'ما أصغر دولة في العالم من حيث المساحة؟', ['الفاتيكان', 'موناكو', 'سان مارينو', 'مالطا']],
  ['geography', 'medium', 'ما عاصمة أستراليا؟', ['كانبرا', 'سيدني', 'ملبورن', 'بيرث']],
  ['geography', 'medium', 'ما أكبر صحراء حارة في العالم؟', ['الصحراء الكبرى', 'صحراء الربع الخالي', 'صحراء كالاهاري', 'صحراء غوبي']],
  ['science', 'easy', 'ما أكبر كوكب في المجموعة الشمسية؟', ['المشتري', 'زحل', 'أورانوس', 'نبتون']],
  ['science', 'medium', 'ما الرمز الكيميائي للذهب؟', ['Au', 'Ag', 'Fe', 'Gd']],
  ['science', 'medium', 'كم تبلغ سرعة الضوء في الفراغ تقريباً؟', ['300 ألف كم في الثانية', '30 ألف كم في الثانية', '3 ملايين كم في الثانية', '3 آلاف كم في الثانية']],
  ['science', 'medium', 'كم عدد عظام جسم الإنسان البالغ عادةً؟', ['206', '201', '212', '196']],
  ['science', 'medium', 'ما الغاز الأكثر وفرة في الغلاف الجوي للأرض؟', ['النيتروجين', 'الأكسجين', 'ثاني أكسيد الكربون', 'الأرجون']],
  ['sports', 'easy', 'كم عدد لاعبي فريق كرة القدم داخل الملعب؟', ['11', '10', '9', '12']],
  ['sports', 'easy', 'كم دقيقة تستمر مباراة كرة القدم الرسمية بدون وقت إضافي؟', ['90', '80', '100', '60']],
  ['history', 'easy', 'في أي سنة انتهت الحرب العالمية الثانية؟', ['1945', '1939', '1918', '1950']],
  ['history', 'medium', 'لأي ملك يُنسب بناء الهرم الأكبر في الجيزة؟', ['خوفو', 'خفرع', 'منقرع', 'رمسيس الثاني']],
  ['history', 'medium', 'في أي سنة حصل نجيب محفوظ على جائزة نوبل في الأدب؟', ['1988', '1978', '1994', '1980']],
  ['entertainment', 'medium', 'من مؤلف كتاب "الأيام"؟', ['طه حسين', 'نجيب محفوظ', 'عباس العقاد', 'توفيق الحكيم']],
  ['general', 'easy', 'كم عدد أضلاع الشكل السداسي؟', ['6', '5', '8', '7']],
  ['general', 'easy', 'كم عدد أيام السنة الميلادية الكبيسة؟', ['366', '365', '364', '367']],
];

async function main() {
  const approve = process.argv.includes('--approve-for-local-testing');
  const existing = await prisma.contentItem.count({ where: { gameId: 'quiz' } });
  if (existing > 0) {
    console.log(`quiz content already present (${existing} items); skipping`);
    return;
  }
  await prisma.contentItem.createMany({
    data: QUESTIONS.map(([category, difficulty, prompt, choices, explanation]) => ({
      gameId: 'quiz',
      category,
      difficulty,
      payload: { prompt, choices, correct: 0, explanation: explanation ?? null },
      status: approve ? ('approved' as const) : ('in_review' as const),
      publishedAt: approve ? new Date() : null,
    })),
  });
  console.log(`inserted ${QUESTIONS.length} sample questions as ${approve ? 'approved (local testing)' : 'in_review'}`);
}

main().finally(() => prisma.$disconnect());
