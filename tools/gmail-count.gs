/* Gmail message counts for the admin page.

   Set up once, signed in to the project's Gmail account:
   1. Go to https://script.google.com and press New project. Name it "Our Futures First inbox count".
   2. Delete what is in the editor, paste this whole file in, and press Save.
   3. Press Deploy > New deployment. Under "Select type" (the gear) choose Web app.
      Execute as: Me. Who has access: Anyone. Press Deploy and allow access when Google asks.
   4. Copy the Web app URL (it ends in /exec) and put it in GMAIL_COUNT near the top of admin.html's script.

   What it shares: only the three numbers below, never names, addresses or message text.
   Anyone with the URL can see those numbers. */

var SKIP = /no-?reply|notifications?@|mailer-daemon|@resend\.|@supabase\.|@cloudflare|@google\.com|@accounts\.google/i;

function doGet() {
  var me = Session.getActiveUser().getEmail().toLowerCase();
  var threads = GmailApp.search('in:inbox -from:me', 0, 500);
  var people = {}, week = {}, cutoff = Date.now() - 7 * 864e5;
  GmailApp.getMessagesForThreads(threads).forEach(function (msgs) {
    msgs.forEach(function (m) {
      var from = (m.getFrom().match(/<([^>]+)>/) || [, m.getFrom()])[1].trim().toLowerCase();
      if (!from || from === me || SKIP.test(from)) return;
      people[from] = true;
      if (m.getDate().getTime() > cutoff) week[from] = true;
    });
  });
  var out = {
    people: Object.keys(people).length,      // different people who have written in
    week: Object.keys(week).length,          // of those, how many wrote in the past 7 days
    unread: GmailApp.getInboxUnreadCount(),  // unread conversations in the inbox
    at: new Date().toISOString()
  };
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(ContentService.MimeType.JSON);
}
