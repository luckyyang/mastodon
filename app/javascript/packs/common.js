import { start } from 'rails-ujs';

// import default stylesheet with variables
require('font-awesome/css/font-awesome.css');
require('mastodon-application-style'); // eslint-disable-line import/no-unresolved

require.context('../images/', true);

start();
