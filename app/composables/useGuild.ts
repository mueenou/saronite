import type { User } from '@supabase/supabase-js'
import type { Guild, GuildRole } from '#shared/types'

type MembershipRow = {
  guild_id: string
  role: GuildRole
  guilds: { id: string, name: string, discord_server_id: string | null } | { id: string, name: string, discord_server_id: string | null }[] | null
  profiles: { display_name: string } | { display_name: string }[] | null
}

export function useGuild() {
  const supabase = useNuxtApp().$supabase
  const user = useState<User | null>('guild:user', () => null)
  const membership = useState<{ guild: Guild, role: GuildRole } | null>('guild:membership', () => null)
  const isLoading = useState<boolean>('guild:loading', () => true)
  const error = useState<string | null>('guild:error', () => null)
  const configured = computed(() => Boolean(supabase))
  const canEdit = computed(() => ['owner', 'admin', 'officer'].includes(membership.value?.role ?? ''))
  const canManageInvites = computed(() => canEdit.value)
  const isOwnerOrAdmin = computed(() => ['owner', 'admin'].includes(membership.value?.role ?? ''))
  const initialized = useState<boolean>('guild:initialized', () => false)
  const listenerInstalled = useState<boolean>('guild:auth-listener-installed', () => false)

  function setError(value: unknown) {
    error.value = value instanceof Error || (value && typeof value === 'object' && 'message' in value)
      ? String((value as { message: unknown }).message)
      : 'Something went wrong. Please try again.'
  }

  async function refreshMembership() {
    if (!supabase || !user.value) {
      membership.value = null
      return
    }

    const { data, error: queryError } = await supabase
      .from('guild_memberships')
      .select('guild_id, role, guilds(id, name, discord_server_id), profiles(display_name)')
      .eq('user_id', user.value.id)
      .maybeSingle()

    if (queryError) throw queryError
    const row = data as unknown as MembershipRow | null
    const joinedGuild = Array.isArray(row?.guilds) ? row.guilds[0] : row?.guilds
    membership.value = row && joinedGuild
      ? {
          guild: {
            id: joinedGuild.id,
            name: joinedGuild.name,
            discordServerId: joinedGuild.discord_server_id ?? null
          },
          role: row.role
        }
      : null
  }

  async function initialize() {
    if (initialized.value) return
    initialized.value = true
    if (!supabase) {
      error.value = 'Supabase is not configured. Copy .env.example to .env and set the project URL and publishable key.'
      isLoading.value = false
      return
    }

    isLoading.value = true
    error.value = null
    try {
      const { data, error: sessionError } = await supabase.auth.getSession()
      if (sessionError) throw sessionError
      user.value = data.session?.user ?? null
      await refreshMembership()

      if (!listenerInstalled.value) {
        listenerInstalled.value = true
        supabase.auth.onAuthStateChange((_event, session) => {
          user.value = session?.user ?? null
          if (!session?.user) {
            membership.value = null
            return
          }
          // Do not await Supabase calls inside its auth-state callback.
          queueMicrotask(() => { void refreshMembership().catch(setError) })
        })
      }
    } catch (cause) {
      setError(cause)
    } finally {
      isLoading.value = false
    }
  }

  async function signIn(email: string, password: string) {
    if (!supabase) return
    error.value = null
    const { data, error: authError } = await supabase.auth.signInWithPassword({ email, password })
    if (authError) throw authError
    user.value = data.session?.user ?? null
    await refreshMembership()
  }

  async function signUp(email: string, password: string, displayName: string) {
    if (!supabase) return { needsEmailConfirmation: false }
    error.value = null
    const { data, error: authError } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { display_name: displayName.trim() } }
    })
    if (authError) throw authError
    user.value = data.session?.user ?? null
    if (data.session) await refreshMembership()
    return { needsEmailConfirmation: !data.session }
  }

  async function signOut() {
    if (!supabase) return
    const { error: authError } = await supabase.auth.signOut()
    if (authError) throw authError
    user.value = null
    membership.value = null
  }

  async function createGuild(name: string, discordServerId: string) {
    if (!supabase) return
    const { error: rpcError } = await supabase.rpc('create_guild', {
      p_name: name,
      p_discord_server_id: discordServerId || null
    })
    if (rpcError) throw rpcError
    await refreshMembership()
  }

  async function joinGuild(inviteCode: string) {
    if (!supabase) return
    const { error: rpcError } = await supabase.rpc('join_guild', { p_invite_code: inviteCode.trim() })
    if (rpcError) throw rpcError
    await refreshMembership()
  }

  async function createInvite(role: 'member' | 'officer') {
    if (!supabase || !membership.value) throw new Error('You must belong to a guild first.')
    const { data, error: rpcError } = await supabase.rpc('create_guild_invite', {
      p_guild_id: membership.value.guild.id,
      p_role: role,
      p_max_uses: 20
    })
    if (rpcError) throw rpcError
    return String(data)
  }

  async function listMembers() {
    if (!supabase || !membership.value) return []
    const { data, error: queryError } = await supabase
      .from('guild_memberships')
      .select('user_id, role, joined_at, profiles(display_name)')
      .eq('guild_id', membership.value.guild.id)
      .order('joined_at')
    if (queryError) throw queryError
    return data as unknown as { user_id: string, role: GuildRole, joined_at: string, profiles: { display_name: string } | null }[]
  }

  async function updateMemberRole(userId: string, role: 'admin' | 'officer' | 'member') {
    if (!supabase || !membership.value) return
    const { error: rpcError } = await supabase.rpc('update_guild_member_role', {
      p_guild_id: membership.value.guild.id,
      p_user_id: userId,
      p_role: role
    })
    if (rpcError) throw rpcError
  }

  return {
    user, membership, isLoading, error, configured, canEdit, canManageInvites, isOwnerOrAdmin,
    initialize, refreshMembership, signIn, signUp, signOut,
    createGuild, joinGuild, createInvite, listMembers, updateMemberRole
  }
}
