importScripts('https://www.gstatic.com/firebasejs/12.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyATw15PaNYvu8BRQhdim1Px2hrGqaHiwIw',
  appId: '1:341161446747:web:17adc2aa0131bb80d69e7e',
  messagingSenderId: '341161446747',
  projectId: 'freshnearby-17349',
  authDomain: 'freshnearby-17349.firebaseapp.com',
  storageBucket: 'freshnearby-17349.firebasestorage.app',
});

firebase.messaging();
