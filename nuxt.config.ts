export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  ssr: false, // the builder is fully client-side for now (localStorage + share links)
  runtimeConfig: {
    public: {
      supabaseUrl: '',
      supabaseAnonKey: ''
    }
  },
  css: ['~/assets/css/main.css'],
  app: {
    head: {
      title: 'Saronite: WotLK raid planner',
      htmlAttrs: { lang: 'en' },
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1' },
        { name: 'description', content: 'Build Wrath of the Lich King raid rosters and check buff and debuff coverage at a glance.' }
      ],
      link: [
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Marcellus&family=Alegreya+Sans:wght@400;500;700&display=swap' }
      ]
    }
  }
})
