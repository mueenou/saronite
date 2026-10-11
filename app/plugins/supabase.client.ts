import { createClient } from '@supabase/supabase-js'

export default defineNuxtPlugin(() => {
  const config = useRuntimeConfig().public
  const supabase = config.supabaseUrl && config.supabaseAnonKey
    ? createClient(String(config.supabaseUrl), String(config.supabaseAnonKey), {
        auth: {
          autoRefreshToken: true,
          detectSessionInUrl: true,
          persistSession: true
        }
      })
    : null

  return { provide: { supabase } }
})
