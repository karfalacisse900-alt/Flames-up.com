// No identity or private club data is exposed on the public fallback page.
const token = location.pathname.match(/^\/tea-invite\/([a-f0-9]{64})\/?$/)?.[1];
if (token && !location.search && !location.hash) {
  const action = document.querySelector('#open');
  action.href = 'captro://tea-invite/' + token;
  action.hidden = false;
} else document.querySelector('#status').textContent = 'This invitation link is invalid. Ask an organizer for a new link.';
