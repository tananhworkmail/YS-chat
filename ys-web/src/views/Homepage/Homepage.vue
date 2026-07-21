<template>
  <div
    class="chat-shell"
    :class="{
      'has-active': activeConversationId && panelMode !== 'contacts',
      'show-directory': panelMode === 'contacts',
      'show-info': infoPanelOpen,
      'is-dragging': isDragging,
    }"
    @dragenter.prevent="onDragEnter"
    @dragover.prevent="onDragOver"
    @dragleave.prevent="onDragLeave"
    @drop.prevent="handleDrop"
  >
    <div v-if="isDragging" class="drop-overlay">
      <UploadCloud :size="42" />
      <strong>{{ homeT("drag.title") }}</strong>
      <span>{{ homeT("drag.description") }}</span>
    </div>

    <div class="notification-stack">
      <button
        v-for="notification in toastNotifications"
        :key="notification.id"
        class="message-toast"
        type="button"
        @click="openNotification(notification)"
      >
        <el-avatar :size="34" :src="notification.avatar || undefined">
          {{ initials(notification.title) }}
        </el-avatar>
        <span>
          <strong>{{ notification.title }}</strong>
          <small>{{ notification.body }}</small>
        </span>
        <X :size="15" @click.stop="dismissNotification(notification.id)" />
      </button>
    </div>

    <div v-if="reminderNotice" class="reminder-call-panel">
      <div class="reminder-call-card">
        <span class="reminder-call-pulse"><AlarmClock :size="28" /></span>
        <small>{{ homeT("reminder.due") }}</small>
        <strong>{{ reminderNotice.title }}</strong>
        <span class="reminder-call-time">{{ formatReminderTime(reminderNotice.remindAt) }}</span>
        <button class="call-control end" type="button" :title="homeT('reminder.dismiss')" @click="dismissReminderNotice">
          <X :size="20" />
        </button>
        <i></i>
      </div>
    </div>

    <div v-if="callState !== 'idle'" class="call-panel" :class="[callState, { video: isVideoCall }]">
      <div v-if="isVideoCall" class="call-video-stage">
        <video ref="remoteVideoRef" class="call-video-remote" autoplay playsinline muted></video>
        <div v-if="callState === 'incoming'" class="call-video-placeholder">
          <Video :size="34" />
          <span>{{ callText("incomingVideo") }}</span>
        </div>
        <video
          v-show="!callCameraOff && callState !== 'incoming'"
          ref="localVideoRef"
          class="call-video-local"
          autoplay
          playsinline
          muted
        ></video>
      </div>
      <div class="call-peer">
        <span class="call-pulse">
          <Video v-if="isVideoCall" :size="18" />
          <PhoneCall v-else :size="18" />
        </span>
        <span>
          <strong>{{ callPeerName }}</strong>
          <small>{{ callStatusLabel }}</small>
        </span>
      </div>
      <div class="call-controls">
        <button
          v-if="callState === 'incoming'"
          class="call-control accept"
          type="button"
          :title="callText('accept')"
          @click="acceptIncomingCall"
        >
          <Phone :size="19" />
        </button>
        <button
          v-if="callState === 'incoming'"
          class="call-control end"
          type="button"
          :title="callText('reject')"
          @click="rejectIncomingCall"
        >
          <PhoneOff :size="19" />
        </button>
        <template v-else>
          <button
            v-if="isVideoCall"
            class="call-control camera"
            :class="{ muted: callCameraOff }"
            type="button"
            :title="callCameraOff ? callText('cameraOn') : callText('cameraOff')"
            @click="toggleCallCamera"
          >
            <VideoOff v-if="callCameraOff" :size="18" />
            <Video v-else :size="18" />
          </button>
          <button
            class="call-control mute"
            :class="{ muted: callMuted }"
            type="button"
            :title="callMuted ? callText('unmute') : callText('mute')"
            @click="toggleCallMute"
          >
            <MicOff v-if="callMuted" :size="18" />
            <Mic v-else :size="18" />
          </button>
          <button
            class="call-control end"
            type="button"
            :title="callText('end')"
            @click="endOrCancelCall"
          >
            <PhoneOff :size="19" />
          </button>
        </template>
      </div>
    </div>

    <audio ref="remoteAudioRef" class="remote-call-audio" autoplay playsinline></audio>

    <nav class="app-rail">
      <div class="rail-logo">
        <BrandLogo size="sm" />
      </div>

      <div class="rail-actions">
        <el-tooltip :content="homeT('rail.chats')" placement="right">
          <button class="rail-button" :class="{ active: panelMode === 'chats' }" type="button" @click="setPanelMode('chats')">
            <MessageCircle :size="22" />
          </button>
        </el-tooltip>
        <el-tooltip :content="homeT('rail.contacts')" placement="right">
          <button class="rail-button" :class="{ active: panelMode === 'contacts' }" type="button" @click="setPanelMode('contacts')">
            <Users :size="22" />
          </button>
        </el-tooltip>
      </div>

      <div class="rail-bottom">
        <el-dropdown class="rail-dropdown" trigger="click" placement="right-start" @command="changeLocale">
          <button
            class="rail-button language-rail-button"
            type="button"
            :aria-label="homeT('language.tooltip')"
            :title="homeT('language.tooltip')"
          >
            <Languages :size="21" />
            <span>{{ currentLangCode }}</span>
          </button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item
                v-for="language in languageOptions"
                :key="language.value"
                :command="language.value"
                :disabled="locale === language.value"
              >
                {{ language.label }}
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-tooltip :content="homeT('rail.profile')" placement="right">
          <button class="rail-button profile-rail-button" type="button" @click="openProfileDialog">
            <el-avatar :size="30" :src="currentUser.avatar || undefined">
              {{ initials(currentUser.fullname || currentUser.userid) }}
            </el-avatar>
          </button>
        </el-tooltip>
        <el-tooltip :content="homeT('rail.logout')" placement="right">
          <button class="rail-button" type="button" @click="handleLogout">
            <LogOut :size="22" />
          </button>
        </el-tooltip>
      </div>
    </nav>

    <aside class="conversation-panel">
      <header class="panel-header">
        <div>
          <p class="eyebrow">YS Chat</p>
          <h1>{{ panelTitle }}</h1>
        </div>
        <div class="panel-actions">
          <el-tooltip :content="homeT('actions.addContact')" placement="bottom">
            <button class="icon-button" type="button" @click="openContactDialog">
              <UserPlus :size="20" />
            </button>
          </el-tooltip>
          <el-tooltip :content="homeT('actions.createGroup')" placement="bottom">
            <button class="icon-button primary" type="button" @click="openGroupDialog">
              <Users :size="20" />
            </button>
          </el-tooltip>
        </div>
      </header>

      <div class="search-box">
        <Search :size="18" />
        <input
          v-if="panelMode === 'contacts'"
          v-model="contactSearchKeyword"
          type="search"
          :placeholder="homeT('search.placeholder')"
        />
        <input v-else v-model="searchKeyword" type="search" :placeholder="homeT('search.chatPlaceholder')" />
        <button v-if="hasPanelSearchText" class="search-clear-button" type="button" :title="homeT('search.clear')" @click="clearPanelSearch">
          <X :size="15" />
        </button>
      </div>

      <nav v-if="panelMode !== 'contacts' && hasSearchKeyword" class="search-scope-tabs" :aria-label="homeT('search.scopeLabel')">
        <button
          v-for="option in searchScopeOptions"
          :key="option.value"
          type="button"
          :class="{ active: searchScope === option.value }"
          @click="searchScope = option.value"
        >
          {{ homeT(option.labelKey) }}
        </button>
      </nav>

      <div v-if="panelMode !== 'contacts' && hasSearchKeyword" class="search-results">
        <div v-if="searchingChat" class="list-state compact">{{ homeT("search.searching") }}</div>

        <section v-if="shouldShowSearchSection('contacts') && chatSearchUserResult" class="result-section">
          <div class="result-title">{{ homeT("search.contacts") }}</div>
          <div class="user-result">
            <div class="avatar-presence-wrap">
              <el-avatar :size="40" :src="chatSearchUserResult.avatar || undefined">
                {{ initials(displayName(chatSearchUserResult)) }}
              </el-avatar>
              <span
                v-if="shouldShowPresence(chatSearchUserResult)"
                class="presence-dot"
                :class="{ online: isUserOnline(chatSearchUserResult) }"
                :title="presenceLabel(chatSearchUserResult)"
              ></span>
            </div>
            <div class="user-result-main">
              <strong>{{ displayName(chatSearchUserResult) }}</strong>
              <span>{{ chatSearchUserResult.userid }}</span>
            </div>
            <button
              v-if="chatSearchUserResult.isContact"
              class="result-action ghost"
              type="button"
              @click="startDirectChat(chatSearchUserResult.userid)"
            >
              {{ homeT("actions.message") }}
            </button>
            <button
              v-else
              class="result-action"
              type="button"
              @click="addContactFromSearchUser(chatSearchUserResult)"
            >
              {{ homeT("actions.add") }}
            </button>
          </div>
        </section>

        <section v-if="shouldShowSearchSection('contacts') && visibleFilteredConversations.length" class="result-section">
          <div class="result-title">{{ homeT("search.conversations") }}</div>
          <button
            v-for="conversation in visibleFilteredConversations"
            :key="conversation.id"
            class="conversation-item"
            :class="{
              active: conversation.id === activeConversationId,
              'has-unread': unreadCount(conversation.id),
            }"
            type="button"
            @click="selectConversation(conversation)"
          >
            <div class="avatar-presence-wrap">
              <div v-if="conversation.type === 'group' && !conversation.avatar" class="conversation-avatar group">
                <Users :size="22" />
                <span>{{ conversation.memberCount }}</span>
              </div>
              <el-avatar v-else class="conversation-avatar" :size="44" :src="conversation.avatar || undefined">
                {{ initials(conversation.name) }}
              </el-avatar>
              <span
                v-if="conversationPresenceUser(conversation)"
                class="presence-dot"
                :class="{ online: isUserOnline(conversationPresenceUser(conversation)) }"
                :title="presenceLabel(conversationPresenceUser(conversation))"
              ></span>
            </div>
            <div class="conversation-main">
              <div class="conversation-top">
                <span class="conversation-name">
                  <Pin v-if="isConversationPinned(conversation)" :size="13" />
                  <BellOff v-if="isConversationMuted(conversation)" :size="13" />
                  <Archive v-if="isConversationArchived(conversation)" :size="13" />
                  {{ conversation.name }}
                </span>
                <div class="conversation-meta">
                  <time>{{ conversationTime(conversation) }}</time>
                  <span v-if="unreadCount(conversation.id)" class="unread-badge">
                    {{ formatUnreadCount(conversation.id) }}
                  </span>
                </div>
              </div>
              <p>{{ lastMessagePreview(conversation) }}</p>
            </div>
          </button>
          <button
            v-if="isAllSearchScope && filteredConversations.length > searchPreviewLimit"
            class="view-all-search"
            type="button"
            @click="searchScope = 'contacts'"
          >
            {{ homeT("search.viewAll") }}
          </button>
        </section>

        <section v-if="shouldShowSearchSection('contacts') && visibleChatSearchContacts.length" class="result-section">
          <div class="result-title">{{ homeT("search.contacts") }}</div>
          <div v-for="contact in visibleChatSearchContacts" :key="contact.userid" class="user-result">
            <div class="avatar-presence-wrap">
              <el-avatar :size="40" :src="contact.avatar || undefined">
                {{ initials(displayName(contact)) }}
              </el-avatar>
              <span
                v-if="shouldShowPresence(contact)"
                class="presence-dot"
                :class="{ online: isUserOnline(contact) }"
                :title="presenceLabel(contact)"
              ></span>
            </div>
            <div class="user-result-main">
              <strong>{{ displayName(contact) }}</strong>
              <span>{{ contact.userid }}</span>
            </div>
            <button class="result-action ghost" type="button" @click="startDirectChat(contact.userid)">
              {{ homeT("actions.message") }}
            </button>
          </div>
          <button
            v-if="isAllSearchScope && chatSearchContacts.length > searchPreviewLimit"
            class="view-all-search"
            type="button"
            @click="searchScope = 'contacts'"
          >
            {{ homeT("search.viewAll") }}
          </button>
        </section>

        <section v-if="shouldShowSearchSection('messages') && visibleChatSearchMessages.length" class="result-section">
          <div class="result-title">{{ homeT("search.messages") }}</div>
          <button
            v-for="message in visibleChatSearchMessages"
            :key="`message-${message.id}`"
            class="search-hit"
            type="button"
            @click="openSearchMessage(message)"
          >
            <div class="search-hit-icon">
              <MessageCircle :size="18" />
            </div>
            <div class="search-hit-main">
              <strong>{{ conversationNameById(message.conversationId) }}</strong>
              <span>{{ message.senderName }} · {{ formatTime(message.createdAt) }}</span>
              <p>{{ messageSearchPreview(message) }}</p>
            </div>
          </button>
          <button
            v-if="isAllSearchScope && chatSearchMessages.length > searchPreviewLimit"
            class="view-all-search"
            type="button"
            @click="searchScope = 'messages'"
          >
            {{ homeT("search.viewAll") }}
          </button>
        </section>

        <section v-if="shouldShowSearchSection('files') && visibleChatSearchFiles.length" class="result-section">
          <div class="result-title">{{ homeT("search.files") }}</div>
          <button
            v-for="result in visibleChatSearchFiles"
            :key="`file-${result.message.id}-${result.attachment.id || result.attachment.fileUrl}`"
            class="search-hit"
            type="button"
            @click="openSearchMessage(result.message)"
          >
            <div class="search-hit-icon" :class="fileKind(result.attachment, result.message.type)">
              <component :is="fileIcon(result.attachment, result.message.type)" :size="18" />
            </div>
            <div class="search-hit-main">
              <strong>{{ result.attachment.relativePath || result.attachment.fileName }}</strong>
              <span>
                {{ conversationNameById(result.message.conversationId) }} ·
                {{ fileKindLabel(result.attachment, result.message.type) }} ·
                {{ formatBytes(result.attachment.fileSize) }}
              </span>
              <p>{{ result.message.senderName }} · {{ formatTime(result.message.createdAt) }}</p>
            </div>
          </button>
          <button
            v-if="isAllSearchScope && chatSearchFiles.length > searchPreviewLimit"
            class="view-all-search"
            type="button"
            @click="searchScope = 'files'"
          >
            {{ homeT("search.viewAll") }}
          </button>
        </section>

        <div v-if="!searchingChat && !hasVisibleSearchResults" class="empty-list">
          <Search :size="28" />
          <span>{{ homeT("search.noResults") }}</span>
        </div>
      </div>

      <template v-else-if="panelMode === 'contacts'">
        <nav class="contact-menu" :aria-label="homeT('rail.contacts')">
          <button
            class="contact-menu-item"
            :class="{ active: contactSection === 'friends' }"
            type="button"
            @click="contactSection = 'friends'"
          >
            <UserRound :size="19" />
            <span>{{ homeT("contacts.friendsList") }}</span>
          </button>
          <button
            class="contact-menu-item"
            :class="{ active: contactSection === 'groups' }"
            type="button"
            @click="contactSection = 'groups'"
          >
            <Users :size="19" />
            <span>{{ homeT("contacts.groupsList") }}</span>
          </button>
        </nav>
      </template>

      <template v-else>
        <div v-if="loadingConversations" class="list-state">{{ homeT("chat.loadingConversations") }}</div>
        <div v-else-if="filteredConversations.length === 0" class="empty-list">
          <MessageCircle :size="28" />
          <span>{{ homeT("chat.noConversations") }}</span>
        </div>

        <div v-else class="conversation-list">
          <button
            v-for="conversation in filteredConversations"
            :key="conversation.id"
            class="conversation-item"
            :class="{
              active: conversation.id === activeConversationId,
              'has-unread': unreadCount(conversation.id),
            }"
            type="button"
            @click="selectConversation(conversation)"
          >
            <div class="avatar-presence-wrap">
              <div v-if="conversation.type === 'group' && !conversation.avatar" class="conversation-avatar group">
                <Users :size="22" />
                <span>{{ conversation.memberCount }}</span>
              </div>
              <el-avatar v-else class="conversation-avatar" :size="44" :src="conversation.avatar || undefined">
                {{ initials(conversation.name) }}
              </el-avatar>
              <span
                v-if="conversationPresenceUser(conversation)"
                class="presence-dot"
                :class="{ online: isUserOnline(conversationPresenceUser(conversation)) }"
                :title="presenceLabel(conversationPresenceUser(conversation))"
              ></span>
            </div>
            <div class="conversation-main">
              <div class="conversation-top">
                <span class="conversation-name">
                  <Pin v-if="isConversationPinned(conversation)" :size="13" />
                  <BellOff v-if="isConversationMuted(conversation)" :size="13" />
                  <Archive v-if="isConversationArchived(conversation)" :size="13" />
                  {{ conversation.name }}
                </span>
                <div class="conversation-meta">
                  <time>{{ conversationTime(conversation) }}</time>
                  <span v-if="unreadCount(conversation.id)" class="unread-badge">
                    {{ formatUnreadCount(conversation.id) }}
                  </span>
                </div>
              </div>
              <p>{{ lastMessagePreview(conversation) }}</p>
            </div>
          </button>
        </div>
      </template>
    </aside>

    <main class="chat-pane">
      <template v-if="panelMode === 'contacts'">
        <section class="directory-pane">
          <header class="directory-header">
            <div class="directory-title">
              <UserRound v-if="contactSection === 'friends'" :size="22" />
              <Users v-else :size="22" />
              <h2>{{ contactDirectoryTitle }}</h2>
            </div>
          </header>

          <div class="directory-content">
            <div class="directory-section-title">{{ contactDirectoryCountLabel }}</div>

            <div class="directory-tabs">
              <button
                :class="{ active: contactSection === 'friends' }"
                type="button"
                @click="contactSection = 'friends'"
              >
                {{ homeT("contacts.friends") }}
              </button>
              <button
                :class="{ active: contactSection === 'groups' }"
                type="button"
                @click="contactSection = 'groups'"
              >
                {{ homeT("contacts.groups") }}
              </button>
            </div>

            <div class="directory-search">
              <Search :size="18" />
              <input
                v-model="contactSearchKeyword"
                type="search"
                :placeholder="contactSection === 'friends' ? homeT('contacts.findFriend') : homeT('contacts.findGroup')"
              />
            </div>

            <template v-if="contactSection === 'friends'">
              <div v-if="loadingContacts" class="list-state">{{ homeT("contacts.loadingFriends") }}</div>
              <div v-else-if="!groupedDirectoryContacts.length" class="empty-list">
                <Users :size="28" />
                <span>{{ homeT("contacts.emptyFriends") }}</span>
              </div>
              <div v-else class="directory-list">
                <section
                  v-for="group in groupedDirectoryContacts"
                  :key="group.letter"
                  class="directory-letter-group"
                >
                  <h3>{{ group.letter }}</h3>
                  <button
                    v-for="contact in group.items"
                    :key="contact.userid"
                    class="directory-item"
                    type="button"
                    @click="startDirectChat(contact.userid)"
                  >
                    <div class="avatar-presence-wrap">
                      <el-avatar :size="42" :src="contact.avatar || undefined">
                        {{ initials(displayName(contact)) }}
                      </el-avatar>
                      <span
                        v-if="shouldShowPresence(contact)"
                        class="presence-dot"
                        :class="{ online: isUserOnline(contact) }"
                        :title="presenceLabel(contact)"
                      ></span>
                    </div>
                    <span>
                      <strong>{{ displayName(contact) }}</strong>
                      <small>{{ contact.userid }}</small>
                    </span>
                  </button>
                </section>
              </div>
            </template>

            <template v-else>
              <div v-if="loadingConversations" class="list-state">{{ homeT("contacts.loadingGroups") }}</div>
              <div v-else-if="!filteredDirectoryGroups.length" class="empty-list">
                <Users :size="28" />
                <span>{{ homeT("contacts.emptyGroups") }}</span>
              </div>
              <div v-else class="directory-list">
                <button
                  v-for="group in filteredDirectoryGroups"
                  :key="group.id"
                  class="directory-item"
                  type="button"
                  @click="openGroupFromDirectory(group)"
                >
                  <div v-if="!group.avatar" class="directory-group-avatar">
                    <Users :size="21" />
                    <em>{{ group.memberCount }}</em>
                  </div>
                  <el-avatar v-else :size="42" :src="group.avatar">
                    {{ initials(group.name) }}
                  </el-avatar>
                  <span>
                    <strong>{{ group.name }}</strong>
                    <small>{{ group.memberCount }} {{ homeT("chat.members") }}</small>
                  </span>
                </button>
              </div>
            </template>
          </div>
        </section>
      </template>

      <template v-else-if="activeConversation">
        <header class="chat-header">
          <button class="mobile-back" type="button" @click="activeConversationId = null">
            <ChevronLeft :size="22" />
          </button>
          <div class="avatar-presence-wrap">
            <el-avatar :size="44" :src="activeConversation.avatar || undefined">
              {{ initials(activeConversation.name) }}
            </el-avatar>
            <span
              v-if="conversationPresenceUser(activeConversation)"
              class="presence-dot"
              :class="{ online: isUserOnline(conversationPresenceUser(activeConversation)) }"
              :title="presenceLabel(conversationPresenceUser(activeConversation))"
            ></span>
          </div>
          <div class="chat-title">
            <h2>{{ activeConversation.name }}</h2>
            <span>{{ activeConversation.memberCount }} {{ homeT("chat.members") }}</span>
          </div>
          <div class="conversation-search">
            <Search :size="16" />
            <input
              v-model="conversationSearchKeyword"
              type="search"
              :placeholder="homeT('chat.searchPlaceholder')"
            />
            <span v-if="conversationSearchKeyword.trim()" class="conversation-search-count">
              {{ conversationSearchPositionLabel }}
            </span>
            <button
              v-if="conversationSearchKeyword.trim()"
              type="button"
              :disabled="!conversationSearchMatches.length"
              :title="homeT('chat.previousSearchResult')"
              @click="goToConversationSearchResult(-1)"
            >
              <ChevronUp :size="15" />
            </button>
            <button
              v-if="conversationSearchKeyword.trim()"
              type="button"
              :disabled="!conversationSearchMatches.length"
              :title="homeT('chat.nextSearchResult')"
              @click="goToConversationSearchResult(1)"
            >
              <ChevronDown :size="15" />
            </button>
            <button
              v-if="conversationSearchKeyword.trim()"
              type="button"
              :title="homeT('search.clear')"
              @click="clearConversationSearch"
            >
              <X :size="15" />
            </button>
          </div>
          <div class="chat-actions">
            <el-tooltip v-if="activeConversation.type === 'direct'" :content="callText('start')" placement="bottom">
              <button class="icon-button" type="button" :disabled="!canStartAudioCall" @click="startAudioCall">
                <Phone :size="20" />
              </button>
            </el-tooltip>
            <el-tooltip v-if="activeConversation.type === 'direct'" :content="callText('startVideo')" placement="bottom">
              <button class="icon-button" type="button" :disabled="!canStartAudioCall" @click="startVideoCall">
                <Video :size="20" />
              </button>
            </el-tooltip>
            <el-tooltip
              v-if="activeConversation.type === 'direct' && directConversationPeer(activeConversation) && !isContactUser(directConversationPeer(activeConversation).userid)"
              :content="homeT('actions.addContact')"
              placement="bottom"
            >
              <button class="icon-button" type="button" @click="addActiveConversationContact">
                <UserPlus :size="20" />
              </button>
            </el-tooltip>
            <el-tooltip v-if="activeConversation.type === 'group'" :content="homeT('chat.addMember')" placement="bottom">
              <button class="icon-button" type="button" @click="openAddMemberDialog">
                <UserPlus :size="20" />
              </button>
            </el-tooltip>
            <el-tooltip :content="homeT('chat.info')" placement="bottom">
              <button class="icon-button" type="button" @click="openInfoPanel">
                <Info :size="20" />
              </button>
            </el-tooltip>
            <el-tooltip :content="homeT('reminder.title')" placement="bottom">
              <button class="icon-button" type="button" @click="openReminderDialog">
                <CalendarClock :size="20" />
              </button>
            </el-tooltip>
          </div>
        </header>

        <div v-if="activePinnedMessage" class="pinned-message-bar">
          <button class="pinned-message-main" type="button" @click="scrollToMessage(activePinnedMessage.id)">
            <Pin :size="15" />
            <span>
              <strong>{{ homeT("chat.pinnedMessage") }}</strong>
              <em>{{ messageReferencePreview(activePinnedMessage) }}</em>
            </span>
          </button>
          <el-popover placement="bottom-end" :width="360" trigger="click">
            <div class="pinned-message-list">
              <strong>{{ homeT("chat.pinnedMessagesCount", { count: activePinnedMessages.length }) }}</strong>
              <button
                v-for="pinned in activePinnedMessages"
                :key="pinned.id"
                type="button"
                @click="scrollToMessage(pinned.id)"
              >
                <Pin :size="14" />
                <span>{{ messageReferencePreview(pinned) }}</span>
                <X :size="15" @click.stop="unpinMessage(pinned)" />
              </button>
            </div>
            <template #reference>
              <button class="pinned-message-count" type="button">
                {{ activePinnedMessages.length }}
                <ChevronDown :size="15" />
              </button>
            </template>
          </el-popover>
          <button
            class="pinned-message-remove"
            type="button"
            :title="homeT('chat.unpinMessage')"
            @click="unpinMessage(activePinnedMessage)"
          >
            <X :size="15" />
          </button>
        </div>

        <div class="message-list-wrap">
        <section ref="messageListRef" class="message-list" :style="messageListStyle" @scroll="handleMessageListScroll">
          <div v-if="loadingMessages" class="message-state">{{ homeT("chat.loadingMessages") }}</div>
          <div v-else-if="messages.length === 0" class="message-state">
            <MessageCircle :size="34" />
            <span>{{ homeT("chat.startConversation") }}</span>
          </div>

          <template v-else>
          <div v-if="loadingOlderMessages" class="message-history-loader">
            {{ homeT("chat.loadingOlderMessages") }}
          </div>
          <div
            v-for="message in messages"
            :id="`message-${message.id}`"
            :key="message.id"
            class="message-row"
            :class="{
              own: isOwnMessage(message),
              'system-message': message.type === 'system',
              'poll-message': message.type === 'poll',
              'search-match': isConversationSearchMatch(message.id),
              'current-search-match': message.id === currentConversationSearchMessageId,
              'pinned-message': isPinnedMessage(message),
              'send-failed': messageDeliveryState(message) === 'failed',
            }"
          >
            <button
              v-if="!isOwnMessage(message) && !isCenteredMessage(message)"
              class="avatar-presence-wrap message-avatar-wrap message-profile-trigger"
              type="button"
              :title="homeT('profile.title')"
              @click="openMessageSenderProfile(message)"
            >
              <el-avatar :size="32" :src="message.senderAvatar || undefined">
                {{ initials(message.senderName) }}
              </el-avatar>
              <span
                class="presence-dot small"
                :class="{ online: isUserOnline(presenceUserByUserid(message.senderUserid)) }"
                :title="presenceLabel(presenceUserByUserid(message.senderUserid))"
              ></span>
            </button>

            <div class="message-stack">
              <button
                v-if="activeConversation.type === 'group' && !isOwnMessage(message) && !isCenteredMessage(message)"
                class="sender-name"
                type="button"
                @click="openMessageSenderProfile(message)"
              >
                {{ message.senderName }}
              </button>

              <div class="message-content-row">
                <div
                  class="message-bubble"
                  :class="[message.type, { 'has-reactions': messageReactionGroups(message).length }]"
                >
                <button
                  v-if="message.replyTo"
                  class="reply-reference"
                  type="button"
                  @click="scrollToMessage(message.replyTo.id)"
                >
                  <strong>{{ message.replyTo.senderName }}</strong>
                  <span>{{ messageReferencePreview(message.replyTo) }}</span>
                </button>

                <div v-if="message.forwardedFrom" class="forwarded-label">
                  <Forward :size="13" />
                  <span>{{ homeT("chat.forwardedFrom", { name: message.forwardedFrom.senderName }) }}</span>
                </div>

                <div v-if="isMessageRecalled(message)" class="message-tombstone">
                  {{ homeT("chat.recalledMessage") }}
                </div>

                <div v-else-if="message.type === 'system'" class="system-notice">
                  {{ message.content }}
                </div>

                <div
                  v-else-if="message.type === 'call'"
                  class="call-message-card"
                  :class="{
                    missed: callMessageInfo(message).status === 'missed',
                    incoming: callMessageDirection(message) === 'incoming',
                    outgoing: callMessageDirection(message) === 'outgoing',
                  }"
                >
                  <span class="call-message-icon">
                    <component :is="callMessageIcon(message)" :size="19" />
                  </span>
                  <span class="call-message-copy">
                    <strong>{{ callMessageTitle(message) }}</strong>
                    <small>
                      {{ callMessageStatus(message) }}
                      <template v-if="callMessageInfo(message).duration > 0">
                        · {{ formatDuration(callMessageInfo(message).duration) }}
                      </template>
                    </small>
                  </span>
                </div>

                <a
                  v-else-if="message.type === 'link'"
                  class="message-link"
                  :href="safeLink(message.content)"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <Link2 :size="16" />
                  <span>{{ message.content }}</span>
                </a>

                <div v-else-if="message.type === 'poll' && message.poll" class="poll-card">
                  <div class="poll-card-header">
                    <ListChecks :size="17" />
                    <span>
                      <strong>{{ message.poll.question || message.content }}</strong>
                      <em v-if="message.poll.isClosed">{{ homeT("poll.closed") }}</em>
                    </span>
                  </div>

                  <div class="poll-options">
                    <label
                      v-for="option in message.poll.options || []"
                      :key="option.id"
                      class="poll-option"
                      :class="{ selected: isPollOptionSelected(message, option), disabled: pollInteractionDisabled(message) }"
                    >
                      <input
                        :type="message.poll.allowMultiple ? 'checkbox' : 'radio'"
                        :name="`poll-${message.id}`"
                        :checked="isPollOptionSelected(message, option)"
                        :disabled="pollInteractionDisabled(message)"
                        @change="votePollOption(message, option, $event)"
                      />
                      <span class="poll-option-main">
                        <span class="poll-option-text">{{ option.text }}</span>
                        <span v-if="message.poll.showVoters && option.voters?.length" class="poll-voters">
                          {{ pollVoterNames(option) }}
                        </span>
                      </span>
                      <span class="poll-option-count">{{ option.voteCount || 0 }}</span>
                      <span class="poll-option-bar" :style="{ width: `${pollOptionPercent(message.poll, option)}%` }"></span>
                    </label>
                  </div>

                  <form
                    v-if="message.poll.allowCustomOptions"
                    class="poll-custom-form"
                    @submit.prevent="submitCustomPollOption(message)"
                  >
                    <input
                      v-model.trim="pollCustomInputs[message.id]"
                      type="text"
                      maxlength="160"
                      :placeholder="homeT('poll.customPlaceholder')"
                      :disabled="pollInteractionDisabled(message)"
                    />
                    <button type="submit" :disabled="pollInteractionDisabled(message)">
                      <Plus :size="16" />
                    </button>
                  </form>

                  <div class="poll-footer">
                    <small class="poll-meta">{{ pollMetaLabel(message.poll) }}</small>
                    <span class="poll-footer-actions">
                      <button
                        class="poll-pin-button"
                        type="button"
                        @click="isPinnedMessage(message) ? unpinMessage(message) : pinMessage(message)"
                      >
                        <Pin :size="14" />
                        <span>{{ isPinnedMessage(message) ? homeT("chat.unpinMessage") : homeT("chat.pinMessage") }}</span>
                      </button>
                      <button
                        v-if="canClosePoll(message)"
                        class="poll-close-button"
                        type="button"
                        :disabled="Boolean(pollVotingMessageIds[message.id])"
                        @click="closePoll(message)"
                      >
                        <X :size="14" />
                        <span>{{ homeT("poll.close") }}</span>
                      </button>
                    </span>
                  </div>
                </div>

                <p v-else-if="message.content" class="message-text">
                  <template
                    v-for="(part, index) in messageTextParts(message.content)"
                    :key="`${message.id}-${index}`"
                  >
                    <button
                      v-if="part.isMention && part.member"
                      class="mention mention-button"
                      type="button"
                      @click="openMemberProfile(part.member)"
                    >
                      {{ part.text }}
                    </button>
                    <span v-else :class="{ mention: part.isMention }">{{ part.text }}</span>
                  </template>
                </p>

                <div
                  v-if="!isMessageRecalled(message) && imageAttachments(message).length"
                  class="image-grid"
                  :class="{ compact: imageAttachments(message).length > 1 }"
                >
                  <div
                    v-for="attachment in imageAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    class="image-card"
                  >
                    <a
                      class="image-preview"
                      :href="attachment.fileUrl"
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                        <img :src="attachment.fileUrl" :alt="attachment.fileName" loading="lazy" decoding="async" />
                    </a>
                    <a
                      class="image-download-button"
                      :href="attachment.fileUrl"
                      :download="downloadFileName(attachment)"
                      target="_blank"
                      rel="noopener noreferrer"
                      :title="homeT('chat.download')"
                      :aria-label="homeT('chat.download')"
                      @click.stop
                    >
                      <Download :size="16" />
                    </a>
                  </div>
                </div>

                <div v-if="!isMessageRecalled(message) && videoAttachments(message).length" class="video-grid">
                  <div
                    v-for="attachment in videoAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    class="video-card"
                  >
                    <video
                      controls
                      preload="metadata"
                      :src="attachment.fileUrl"
                    ></video>
                    <a
                      class="image-download-button"
                      :href="attachment.fileUrl"
                      :download="downloadFileName(attachment)"
                      target="_blank"
                      rel="noopener noreferrer"
                      :title="homeT('chat.download')"
                      :aria-label="homeT('chat.download')"
                      @click.stop
                    >
                      <Download :size="16" />
                    </a>
                  </div>
                </div>

                <div v-if="!isMessageRecalled(message) && voiceAttachments(message).length" class="voice-list">
                  <div
                    v-for="attachment in voiceAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    class="voice-player"
                  >
                    <div class="voice-icon">
                      <FileAudio :size="18" />
                    </div>
                    <audio controls preload="metadata" :src="attachment.fileUrl"></audio>
                    <a
                      class="download-button"
                      :href="attachment.fileUrl"
                      :download="downloadFileName(attachment)"
                      target="_blank"
                      rel="noopener noreferrer"
                      :title="homeT('chat.download')"
                    >
                      <Download :size="16" />
                    </a>
                  </div>
                </div>

                <div v-if="!isMessageRecalled(message) && fileAttachments(message).length" class="attachment-list">
                  <div
                    v-for="attachment in fileAttachments(message)"
                    :key="attachment.id || attachment.fileUrl"
                    class="attachment-item"
                    :class="fileKind(attachment, message.type)"
                  >
                    <div class="attachment-icon">
                      <component :is="fileIcon(attachment, message.type)" :size="19" />
                      <small v-if="fileBadge(attachment, message.type)" class="attachment-badge">
                        {{ fileBadge(attachment, message.type) }}
                      </small>
                    </div>
                    <div class="attachment-meta">
                      <a :href="attachment.fileUrl" target="_blank" rel="noopener noreferrer">
                        {{ attachment.relativePath || attachment.fileName }}
                      </a>
                      <span>
                        {{ fileKindLabel(attachment, message.type) }} · {{ formatBytes(attachment.fileSize) }}
                      </span>
                    </div>
                    <a
                      class="download-button"
                      :href="attachment.fileUrl"
                      :download="downloadFileName(attachment)"
                      target="_blank"
                      rel="noopener noreferrer"
                      :title="homeT('chat.download')"
                    >
                      <Download :size="16" />
                    </a>
                  </div>
                </div>

                <div v-if="messageReactionGroups(message).length" class="message-reactions">
                  <el-popover
                    trigger="click"
                    placement="bottom"
                    :width="300"
                    popper-class="reaction-detail-popper"
                  >
                    <template #reference>
                      <button
                        class="reaction-summary-button"
                        type="button"
                        :class="{ mine: messageReactionGroups(message).some((reaction) => reaction.reactedByMe) }"
                        :aria-label="homeT('chat.viewReactions')"
                      >
                        <span class="reaction-summary-emojis">
                          <span
                            v-for="reaction in compactMessageReactions(message)"
                            :key="`${message.id}-${reaction.emoji}`"
                          >{{ reaction.emoji }}</span>
                        </span>
                        <small>{{ totalMessageReactions(message) }}</small>
                      </button>
                    </template>
                    <div class="reaction-detail reaction-overview">
                      <strong>{{ homeT("chat.allReactions") }} · {{ totalMessageReactions(message) }}</strong>
                      <section
                        v-for="reaction in messageReactionGroups(message)"
                        :key="`${message.id}-detail-${reaction.emoji}`"
                        class="reaction-detail-group"
                      >
                        <div class="reaction-detail-heading">
                          <span>{{ reaction.emoji }}</span>
                          <b>{{ reaction.count }}</b>
                          <button
                            class="reaction-detail-toggle"
                            type="button"
                            :disabled="Boolean(reactionPending[`${message.id}:${reaction.emoji}`])"
                            @click="toggleReaction(message, reaction.emoji, reaction.reactedByMe)"
                          >
                            {{ reaction.reactedByMe ? homeT("chat.removeMyReaction") : homeT("chat.addMyReaction") }}
                          </button>
                        </div>
                        <ul>
                          <li v-for="user in reactionUsers(reaction)" :key="user.userid">
                            <el-avatar :size="25" :src="user.avatar || undefined">
                              {{ initials(user.fullname) }}
                            </el-avatar>
                            <span>{{ user.fullname }}</span>
                          </li>
                        </ul>
                      </section>
                    </div>
                  </el-popover>
                </div>

                <time>
                  {{ formatTime(message.createdAt) }}
                  <button
                    v-if="message.editedAt || message.edited_at"
                    class="message-edited-link"
                    type="button"
                    @click.stop="openMessageEditHistory(message)"
                  >
                    · {{ homeT("chat.edited") }}
                  </button>
                </time>
              </div>
              <div v-if="!isCenteredMessage(message)" class="message-actions">
                <el-dropdown
                  v-if="!isMessageRecalled(message)"
                  trigger="click"
                  placement="top"
                  @command="(emoji) => toggleReaction(message, emoji)"
                >
                  <button class="message-action-button" type="button" :title="homeT('chat.addReaction')">
                    <SmilePlus :size="15" />
                  </button>
                  <template #dropdown>
                    <el-dropdown-menu class="reaction-picker-menu">
                      <el-dropdown-item v-for="emoji in quickReactionEmojis" :key="emoji" :command="emoji">
                        <span class="reaction-picker-emoji">{{ emoji }}</span>
                      </el-dropdown-item>
                    </el-dropdown-menu>
                  </template>
                </el-dropdown>
                <el-tooltip :content="homeT('chat.reply')" placement="top">
                  <button class="message-action-button" type="button" @click="startReply(message)">
                    <Reply :size="15" />
                  </button>
                </el-tooltip>
                <el-tooltip :content="homeT('chat.forward')" placement="top">
                  <button class="message-action-button" type="button" @click="openForwardDialog(message)">
                    <Forward :size="15" />
                  </button>
                </el-tooltip>
                <el-dropdown
                  trigger="click"
                  placement="top"
                  @command="(command) => handleMessageOption(command, message)"
                >
                  <button class="message-action-button" type="button" :title="homeT('chat.moreActions')">
                    <MoreHorizontal :size="16" />
                  </button>
                  <template #dropdown>
                    <el-dropdown-menu>
                      <el-dropdown-item :command="isPinnedMessage(message) ? 'unpin' : 'pin'">
                        <Pin :size="14" />
                        <span>{{ isPinnedMessage(message) ? homeT("chat.unpinMessage") : homeT("chat.pinMessage") }}</span>
                      </el-dropdown-item>
                      <el-dropdown-item command="copy">
                        <Copy :size="14" />
                        <span>{{ homeT("chat.copyMessage") }}</span>
                      </el-dropdown-item>
                      <el-dropdown-item
                        v-if="message.editedAt || message.edited_at"
                        command="editHistory"
                      >
                        <History :size="14" />
                        <span>{{ homeT("chat.editHistory") }}</span>
                      </el-dropdown-item>
                      <el-dropdown-item v-if="canEditMessage(message)" command="edit" divided>
                        <Pencil :size="14" />
                        <span>{{ homeT("chat.editMessage") }}</span>
                      </el-dropdown-item>
                      <el-dropdown-item v-if="canRecallMessage(message)" command="recall">
                        <Undo2 :size="14" />
                        <span>{{ homeT("chat.recallMessage") }}</span>
                      </el-dropdown-item>
                      <el-dropdown-item command="deleteForMe" divided>
                        <Trash2 :size="14" />
                        <span>{{ homeT("chat.deleteForMe") }}</span>
                      </el-dropdown-item>
                    </el-dropdown-menu>
                  </template>
                </el-dropdown>
                </div>
              </div>
              <div v-if="isOwnMessage(message) && message.type !== 'system'" class="message-delivery-status" :class="messageDeliveryState(message)">
                <button
                  v-if="messageDeliveryState(message) === 'failed'"
                  class="message-retry-button"
                  type="button"
                  @click="retryPendingMessage(message)"
                >
                  <RefreshCw :size="13" />
                  {{ homeT("chat.retrySend") }}
                </button>
                <el-popover
                  v-else-if="canShowMessageReaders(message)"
                  trigger="click"
                  placement="bottom"
                  :width="270"
                  popper-class="message-readers-popper"
                >
                  <template #reference>
                    <button class="message-readers-button" type="button">
                      <CheckCheck :size="14" />
                      <span>{{ messageStatusLabel(message) }}</span>
                    </button>
                  </template>
                  <div class="message-readers-detail">
                    <strong>{{ homeT("chat.readBy") }} · {{ messageReadUsers(message).length }}</strong>
                    <ul>
                      <li v-for="user in messageReadUsers(message)" :key="user.userid">
                        <el-avatar :size="28" :src="user.avatar || undefined">
                          {{ initials(user.fullname) }}
                        </el-avatar>
                        <span>
                          <b>{{ user.fullname }}</b>
                          <small v-if="user.readAt">{{ formatTime(user.readAt) }}</small>
                        </span>
                      </li>
                    </ul>
                  </div>
                </el-popover>
                <template v-else>
                  <CheckCheck v-if="messageDeliveryState(message) === 'read'" :size="14" />
                  <Check v-else :size="14" />
                  <span>{{ messageStatusLabel(message) }}</span>
                </template>
              </div>
            </div>
          </div>
          </template>
        </section>
        <button
          v-if="showLatestButton"
          class="latest-message-button"
          type="button"
          :aria-label="homeT('chat.scrollToLatest')"
          :title="homeT('chat.scrollToLatest')"
          @click="scrollToBottom"
        >
          <ChevronDown :size="21" />
          <span v-if="newMessagesBelowCount" class="latest-message-badge">
            {{ newMessagesBelowCount > 99 ? '99+' : newMessagesBelowCount }}
          </span>
        </button>
        </div>

        <div v-if="typingIndicatorText" class="typing-indicator" aria-live="polite">
          <span><i></i><i></i><i></i></span>
          {{ typingIndicatorText }}
        </div>

        <footer class="composer">
          <div v-if="replyingTo" class="reply-compose">
            <Reply :size="17" />
            <div>
              <strong>{{ homeT("chat.replyTo", { name: replyingTo.senderName }) }}</strong>
              <span>{{ messageReferencePreview(replyingTo) }}</span>
            </div>
            <button type="button" @click="cancelReply">
              <X :size="15" />
            </button>
          </div>

          <div v-if="pendingAttachments.length" class="pending-files">
            <div
              v-for="attachment in pendingAttachments"
              :key="attachment.fileUrl"
              class="pending-file"
              :class="fileKind(attachment, pendingAttachmentType)"
            >
              <component :is="fileIcon(attachment, pendingAttachmentType)" :size="16" />
              <span>{{ attachment.relativePath || attachment.fileName }}</span>
              <small>{{ fileKindLabel(attachment, pendingAttachmentType) }}</small>
              <button type="button" @click="removePendingAttachment(attachment.fileUrl)">
                <X :size="14" />
              </button>
            </div>
          </div>

          <div v-if="isRecording" class="voice-recording">
            <span class="record-dot"></span>
            <strong>{{ recordingDurationLabel }}</strong>
            <span>{{ homeT("chat.recording") }}</span>
            <button type="button" :aria-label="homeT('chat.cancelRecording')" @click="cancelVoiceRecording">
              <X :size="16" />
            </button>
          </div>

          <div class="composer-body">
            <div class="composer-tools">
              <el-tooltip :content="homeT('chat.sendFile')" placement="top">
                <button class="tool-button" type="button" :disabled="isRecording" @click="fileInputRef?.click()">
                  <Paperclip :size="20" />
                </button>
              </el-tooltip>
              <el-tooltip :content="homeT('chat.sendFolder')" placement="top">
                <button class="tool-button" type="button" :disabled="isRecording" @click="folderInputRef?.click()">
                  <FolderUp :size="20" />
                </button>
              </el-tooltip>
              <el-tooltip v-if="activeConversation.type === 'group'" :content="homeT('chat.createPoll')" placement="top">
                <button class="tool-button" type="button" :disabled="isRecording || sending" @click="openPollDialog">
                  <ListChecks :size="20" />
                </button>
              </el-tooltip>
              <el-tooltip :content="isRecording ? homeT('chat.stopSendVoice') : homeT('chat.recordVoice')" placement="top">
                <button
                  class="tool-button voice-record-button"
                  :class="{ active: isRecording, recording: isRecording }"
                  type="button"
                  :disabled="!isRecording && (sending || uploading || preparingRecording)"
                  @click="toggleVoiceRecording"
                >
                  <Square v-if="isRecording" :size="18" />
                  <Mic v-else :size="20" />
                </button>
              </el-tooltip>
            </div>

            <div class="composer-input-wrap">
              <div v-if="mentionActive && mentionSuggestions.length" class="mention-menu">
                <button
                  v-for="(member, index) in mentionSuggestions"
                  :key="mentionOptionKey(member)"
                  :class="{ selected: index === mentionSelectedIndex }"
                  type="button"
                  @mousedown.prevent="insertMention(member)"
                >
                  <span v-if="isAllMentionOption(member)" class="mention-all-icon">
                    <Users :size="16" />
                  </span>
                  <el-avatar v-else :size="28" :src="member.avatar || undefined">
                    {{ initials(displayName(member)) }}
                  </el-avatar>
                  <span>
                    <strong>{{ mentionOptionName(member) }}</strong>
                    <small>{{ mentionOptionDetail(member) }}</small>
                  </span>
                </button>
              </div>

              <textarea
                ref="composerInputRef"
                v-model="composerText"
                rows="1"
                :placeholder="homeT('chat.composerPlaceholder')"
                @input="handleComposerInput"
                @click="updateMentionState"
                @keyup="updateMentionState"
                @keydown.down="handleMentionArrow($event, 1)"
                @keydown.up="handleMentionArrow($event, -1)"
                @keydown.tab="handleMentionTab"
                @keydown.enter.exact.prevent="handleComposerEnter"
                @keydown.esc="closeMentionMenu"
              ></textarea>
            </div>

            <button
              class="send-button"
              type="button"
              :disabled="sending || uploading || isRecording"
              @click="sendCurrentMessage"
            >
              <SendHorizontal :size="20" />
            </button>
          </div>

          <input
            ref="fileInputRef"
            hidden
            multiple
            type="file"
            @change="handleFilesSelected($event, 'file')"
          />
          <input
            ref="folderInputRef"
            hidden
            multiple
            directory
            webkitdirectory
            type="file"
            @change="handleFilesSelected($event, 'folder')"
          />
        </footer>
      </template>

      <section v-else class="empty-chat">
        <div class="welcome-copy">
          <BrandLogo size="xl" />
          <h2>{{ homeT("chat.welcomeTitle") }}</h2>
          <p>{{ homeT("chat.welcomeText") }}</p>
        </div>
        <MessageCircle :size="44" />
        <h2>{{ homeT("chat.chooseConversationTitle") }}</h2>
        <p>{{ homeT("chat.chooseConversationText") }}</p>
      </section>
    </main>

    <button
      v-if="activeConversation && panelMode !== 'contacts'"
      class="info-backdrop"
      type="button"
      :aria-label="homeT('chat.closeInfo')"
      @click="infoPanelOpen = false"
    ></button>

    <aside class="info-panel" v-if="activeConversation && panelMode !== 'contacts'">
      <button class="info-panel-close" type="button" :aria-label="homeT('chat.closeInfo')" @click="infoPanelOpen = false">
        <X :size="18" />
      </button>
      <div v-if="loadingInfoPanelHistory" class="message-history-loader info-history-loader">
        {{ homeT("chat.loadingOlderMessages") }}
      </div>
      <template v-if="infoPanelView === 'storage'">
        <section class="storage-view">
          <header class="storage-header">
            <button type="button" :aria-label="homeT('actions.back')" @click="closeStorageView">
              <ChevronLeft :size="22" />
            </button>
            <h3>{{ homeT("info.storage") }}</h3>
          </header>

          <nav class="storage-tabs" :aria-label="homeT('info.storage')">
            <button
              v-for="tab in storageTabs"
              :key="tab.value"
              type="button"
              :class="{ active: storageTab === tab.value }"
              @click="storageTab = tab.value"
            >
              {{ homeT(tab.labelKey) }}
            </button>
          </nav>

          <div class="storage-content">
            <template v-if="activeStorageGroups.length">
              <section v-for="group in activeStorageGroups" :key="group.key" class="storage-group">
                <h4>{{ group.label }}</h4>

                <div v-if="storageTab === 'media'" class="storage-media-grid">
                  <div
                    v-for="file in group.items"
                    :key="file.fileUrl"
                    class="shared-media-item"
                  >
                    <a
                      class="shared-media-preview"
                      :href="file.fileUrl"
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <img v-if="isImageAttachment(file)" :src="file.fileUrl" :alt="file.fileName" loading="lazy" decoding="async" />
                      <span v-else>
                        <FileVideo :size="24" />
                      </span>
                    </a>
                    <a
                      class="shared-media-download"
                      :href="file.fileUrl"
                      :download="downloadFileName(file)"
                      target="_blank"
                      rel="noopener noreferrer"
                      :title="homeT('chat.download')"
                      :aria-label="homeT('chat.download')"
                      @click.stop
                    >
                      <Download :size="14" />
                    </a>
                  </div>
                </div>

                <div v-else-if="storageTab === 'polls'" class="storage-list">
                  <button
                    v-for="item in group.items"
                    :key="`poll-${item.id}`"
                    class="storage-list-item poll-storage-item"
                    type="button"
                    @click="goToStoredMessage(item)"
                  >
                    <span class="shared-file-icon poll">
                      <ListChecks :size="16" />
                    </span>
                    <span>
                      <strong>{{ item.poll?.question || item.content }}</strong>
                      <em>{{ pollMetaLabel(item.poll || {}) }}<template v-if="item.poll?.isClosed"> · {{ homeT("poll.closed") }}</template></em>
                    </span>
                  </button>
                </div>

                <div v-else class="storage-list">
                  <a
                    v-for="item in group.items"
                    :key="storageItemKey(item)"
                    class="storage-list-item"
                    :href="storageTab === 'links' ? safeLink(item.content) : item.fileUrl"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    <span
                      class="shared-file-icon"
                      :class="storageTab === 'links' ? 'link' : fileKind(item, 'file')"
                    >
                      <Link2 v-if="storageTab === 'links'" :size="16" />
                      <component :is="fileIcon(item, 'file')" v-else :size="16" />
                      <small v-if="storageTab !== 'links' && fileBadge(item, 'file')">{{ fileBadge(item, 'file') }}</small>
                    </span>
                    <span>
                      <strong>{{ storageTab === 'links' ? item.content : item.relativePath || item.fileName }}</strong>
                      <em v-if="storageTab !== 'links'">{{ fileKindLabel(item, 'file') }} · {{ formatBytes(item.fileSize) }}</em>
                    </span>
                  </a>
                </div>
              </section>
            </template>
            <p v-else class="muted storage-empty">{{ activeStorageEmptyText }}</p>
          </div>
        </section>
      </template>
      <template v-else>
      <div class="profile-block">
        <div
          v-if="activeConversation.type === 'group' || activeConversation.type === 'direct'"
          class="conversation-cover"
          :class="{ empty: !activeConversation.background }"
        >
          <img v-if="activeConversation.background" :src="activeConversation.background" alt="" />
          <button
            v-if="activeConversation.type === 'group' || activeConversation.type === 'direct'"
            class="cover-upload-button"
            type="button"
            @click="groupBackgroundInputRef?.click()"
          >
            <Camera :size="15" />
          </button>
        </div>
        <div class="conversation-avatar-editor" :class="{ 'with-cover': activeConversation.type === 'group' || activeConversation.type === 'direct' }">
          <el-avatar :size="72" :src="activeConversation.avatar || undefined">
          {{ initials(activeConversation.name) }}
          </el-avatar>
          <span
            v-if="conversationPresenceUser(activeConversation)"
            class="presence-dot large"
            :class="{ online: isUserOnline(conversationPresenceUser(activeConversation)) }"
            :title="presenceLabel(conversationPresenceUser(activeConversation))"
          ></span>
          <button
            v-if="activeConversation.type === 'group'"
            class="avatar-upload-button mini"
            type="button"
            @click="groupAvatarInputRef?.click()"
          >
            <Camera :size="15" />
          </button>
        </div>
        <div class="profile-title-row">
          <h3>{{ activeConversation.name }}</h3>
          <el-tooltip
            v-if="activeConversation.type === 'direct' && directConversationPeer(activeConversation) && isContactUser(directConversationPeer(activeConversation).userid)"
            :content="homeT('info.setNickname')"
            placement="top"
          >
            <button
              class="profile-nickname-button"
              type="button"
              :aria-label="homeT('info.setNickname')"
              @click="openNicknameDialog(directConversationPeer(activeConversation), 'contact')"
            >
              <Pencil :size="15" />
            </button>
          </el-tooltip>
        </div>
        <input
          ref="groupAvatarInputRef"
          hidden
          accept="image/*"
          type="file"
          @change="handleGroupImageSelected($event, 'avatar')"
        />
        <input
          ref="groupBackgroundInputRef"
          hidden
          accept="image/*"
          type="file"
          @change="handleGroupImageSelected($event, 'background')"
        />
        <span v-if="activeConversation.type === 'group'">
          {{ activeConversation.memberCount }} {{ homeT("chat.members") }}
        </span>
        <span v-else>{{ directConversationPeer(activeConversation)?.userid }}</span>
      </div>

      <section class="info-section conversation-user-settings">
        <div class="section-title">
          <h4>{{ homeT("info.personalSettings") }}</h4>
        </div>
        <div class="conversation-setting-actions">
          <button
            type="button"
            :class="{ active: isConversationMuted(activeConversation) }"
            :disabled="settingsSaving"
            @click="toggleConversationMute"
          >
            <Bell v-if="isConversationMuted(activeConversation)" :size="17" />
            <BellOff v-else :size="17" />
            <span>{{ isConversationMuted(activeConversation) ? homeT("info.unmute") : homeT("info.mute8Hours") }}</span>
          </button>
          <button
            type="button"
            :class="{ active: isConversationPinned(activeConversation) }"
            :disabled="settingsSaving"
            @click="toggleConversationPin"
          >
            <Pin :size="17" />
            <span>{{ isConversationPinned(activeConversation) ? homeT("info.unpinConversation") : homeT("info.pinConversation") }}</span>
          </button>
          <button
            type="button"
            :class="{ active: isConversationArchived(activeConversation) }"
            :disabled="settingsSaving"
            @click="toggleConversationArchive"
          >
            <ArchiveRestore v-if="isConversationArchived(activeConversation)" :size="17" />
            <Archive v-else :size="17" />
            <span>{{ isConversationArchived(activeConversation) ? homeT("info.unarchive") : homeT("info.archive") }}</span>
          </button>
        </div>
      </section>

      <section v-if="activeConversation.type === 'group'" class="info-section">
        <div class="section-title">
          <h4>{{ homeT("info.groupMembers") }}</h4>
          <button v-if="activeConversation.type === 'group'" type="button" @click="openAddMemberDialog">
            <UserPlus :size="16" />
          </button>
        </div>
        <button
          v-if="activeConversation.type === 'group'"
          class="member-count-button"
          type="button"
          @click="membersExpanded = !membersExpanded"
        >
          <Users :size="20" />
          <strong>{{ activeConversation.memberCount }} {{ homeT("chat.members") }}</strong>
        </button>
        <div v-if="membersExpanded" class="member-list">
          <div
            v-for="member in activeConversation.members"
            :key="member.userid"
            class="member-item"
            role="button"
            tabindex="0"
            @click="openMemberProfile(member)"
            @keydown.enter="openMemberProfile(member)"
            @keydown.space.prevent="openMemberProfile(member)"
          >
            <div class="avatar-presence-wrap">
              <el-avatar :size="32" :src="member.avatar || undefined">
                {{ initials(displayName(member)) }}
              </el-avatar>
              <span
                v-if="shouldShowPresence(member)"
                class="presence-dot small"
                :class="{ online: isUserOnline(member) }"
                :title="presenceLabel(member)"
              ></span>
            </div>
            <div class="member-meta">
              <strong>{{ displayName(member) }}</strong>
              <span>{{ member.nickname && member.fullname ? `${member.fullname} · ${member.userid}` : member.userid }}</span>
              <small
                v-if="shouldShowPresence(member)"
                class="presence-text"
                :class="{ online: isUserOnline(member) }"
              >
                {{ presenceLabel(member) }}
              </small>
            </div>
            <el-tooltip :content="homeT('info.setNickname')" placement="left">
              <button
                class="member-action-button"
                type="button"
                :aria-label="homeT('info.setNicknameFor', { name: member.fullname || member.userid })"
                @click.stop="openNicknameDialog(member)"
              >
                <Pencil :size="15" />
              </button>
            </el-tooltip>
            <el-tooltip
              v-if="isCurrentUserGroupOwner && !useridsMatch(member.userid, currentUserid)"
              :content="homeT('info.removeMember')"
              placement="left"
            >
              <button
                class="member-action-button danger"
                type="button"
                :aria-label="homeT('info.removeMemberFromGroup', { name: member.fullname || member.userid })"
                @click.stop="removeMemberFromGroup(member)"
              >
                <Trash2 :size="15" />
              </button>
            </el-tooltip>
          </div>
        </div>
      </section>

      <section v-if="activeConversation.type === 'group'" class="info-section">
        <div class="section-title">
          <h4>{{ homeT("info.polls") }}</h4>
          <button
            v-if="allSharedPolls.length > sharedPreviewLimit"
            class="section-text-button"
            type="button"
            @click="openStorageView('polls')"
          >
            {{ homeT("info.viewAll") }}
          </button>
        </div>
        <div v-if="sharedPolls.length" class="shared-files shared-polls">
          <button
            v-for="pollMessage in sharedPolls"
            :key="pollMessage.id"
            type="button"
            @click="goToStoredMessage(pollMessage)"
          >
            <span class="shared-file-icon poll">
              <ListChecks :size="16" />
            </span>
            <span>
              <strong>{{ pollMessage.poll?.question || pollMessage.content }}</strong>
              <em>{{ pollMetaLabel(pollMessage.poll || {}) }}<template v-if="pollMessage.poll?.isClosed"> · {{ homeT("poll.closed") }}</template></em>
            </span>
          </button>
        </div>
        <p v-else class="muted">{{ homeT("info.noPolls") }}</p>
      </section>

      <section class="info-section">
        <div class="section-title">
          <h4>{{ homeT("info.media") }}</h4>
          <button
            v-if="allSharedMedia.length > sharedPreviewLimit"
            class="section-text-button"
            type="button"
            @click="openStorageView('media')"
          >
            {{ homeT("info.viewAll") }}
          </button>
        </div>
        <div v-if="sharedMedia.length" class="shared-media-grid">
          <div
            v-for="file in sharedMedia"
            :key="file.fileUrl"
            class="shared-media-item"
          >
            <a
              class="shared-media-preview"
              :href="file.fileUrl"
              target="_blank"
              rel="noopener noreferrer"
            >
              <img v-if="isImageAttachment(file)" :src="file.fileUrl" :alt="file.fileName" loading="lazy" decoding="async" />
              <span v-else>
                <FileVideo :size="22" />
              </span>
            </a>
            <a
              class="shared-media-download"
              :href="file.fileUrl"
              :download="downloadFileName(file)"
              target="_blank"
              rel="noopener noreferrer"
              :title="homeT('chat.download')"
              :aria-label="homeT('chat.download')"
              @click.stop
            >
              <Download :size="14" />
            </a>
          </div>
        </div>
        <p v-else class="muted">{{ homeT("info.noMedia") }}</p>
      </section>

      <section class="info-section">
        <div class="section-title">
          <h4>{{ homeT("info.files") }}</h4>
          <button
            v-if="allSharedDocuments.length > sharedPreviewLimit"
            class="section-text-button"
            type="button"
            @click="openStorageView('files')"
          >
            {{ homeT("info.viewAll") }}
          </button>
        </div>
        <div v-if="sharedDocuments.length" class="shared-files">
          <a
            v-for="file in sharedDocuments"
            :key="file.fileUrl"
            :href="file.fileUrl"
            target="_blank"
            rel="noopener noreferrer"
          >
            <span class="shared-file-icon" :class="fileKind(file, 'file')">
              <component :is="fileIcon(file, 'file')" :size="16" />
              <small v-if="fileBadge(file, 'file')">{{ fileBadge(file, 'file') }}</small>
            </span>
            <span>{{ file.relativePath || file.fileName }}</span>
          </a>
        </div>
        <p v-else class="muted">{{ homeT("info.noFiles") }}</p>
      </section>

      <section class="info-section">
        <div class="section-title">
          <h4>{{ homeT("info.links") }}</h4>
          <button
            v-if="allSharedLinks.length > sharedPreviewLimit"
            class="section-text-button"
            type="button"
            @click="openStorageView('links')"
          >
            {{ homeT("info.viewAll") }}
          </button>
        </div>
        <div v-if="sharedLinks.length" class="shared-files">
          <a
            v-for="link in sharedLinks"
            :key="`${link.id}-${link.content}`"
            :href="safeLink(link.content)"
            target="_blank"
            rel="noopener noreferrer"
          >
            <span class="shared-file-icon link">
              <Link2 :size="16" />
            </span>
            <span>{{ link.content }}</span>
          </a>
        </div>
        <p v-else class="muted">{{ homeT("info.noLinks") }}</p>
      </section>
      </template>
    </aside>

    <el-dialog v-model="profileDialogVisible" :title="homeT('profile.title')" width="460px" class="chat-dialog">
      <div class="profile-settings">
        <div class="avatar-editor">
          <el-avatar :size="84" :src="profileForm.avatar || undefined">
            {{ initials(profileForm.fullname || profileForm.userid) }}
          </el-avatar>
          <button class="avatar-upload-button" type="button" @click="avatarInputRef?.click()">
            <Camera :size="17" />
            {{ homeT("profile.changePhoto") }}
          </button>
          <input
            ref="avatarInputRef"
            hidden
            accept="image/*"
            type="file"
            @change="handleAvatarSelected"
          />
        </div>

        <div class="dialog-form language-form">
          <label>{{ homeT("language.label") }}</label>
          <div class="language-selector">
            <button
              v-for="language in languageOptions"
              :key="language.value"
              :class="{ active: locale === language.value }"
              type="button"
              @click="changeLocale(language.value)"
            >
              <span>{{ language.short }}</span>
              <strong>{{ language.label }}</strong>
            </button>
          </div>
        </div>

        <div class="dialog-form">
          <label>{{ homeT("profile.userid") }}</label>
          <input v-model="profileForm.userid" disabled type="text" />

          <label>{{ homeT("profile.displayName") }}</label>
          <input v-model.trim="profileForm.fullname" type="text" :placeholder="homeT('profile.displayNamePlaceholder')" />
          <button class="dialog-button primary full-width" type="button" @click="saveProfile">
            {{ homeT("profile.saveProfile") }}
          </button>
        </div>

        <div class="dialog-form password-action-form">
          <button class="password-open-button" type="button" @click="openPasswordDialog">
            <KeyRound :size="17" />
            <span>{{ homeT("profile.changePassword") }}</span>
          </button>
        </div>
      </div>
    </el-dialog>

    <el-dialog
      v-model="memberProfileDialogVisible"
      :title="homeT('profile.title')"
      width="380px"
      class="chat-dialog"
    >
      <div v-if="memberProfileTarget" class="member-profile-card">
        <el-avatar :size="82" :src="memberProfileTarget.avatar || undefined">
          {{ initials(displayName(memberProfileTarget)) }}
        </el-avatar>
        <strong>{{ displayName(memberProfileTarget) }}</strong>
        <span>{{ memberProfileTarget.userid }}</span>
        <small
          class="member-profile-presence"
          :class="{ online: isUserOnline(memberProfileTarget) }"
        >
          {{ presenceLabel(memberProfileTarget) }}
        </small>
        <div class="member-profile-actions">
          <button
            v-if="!useridsMatch(memberProfileTarget.userid, currentUserid) && !isContactUser(memberProfileTarget.userid)"
            class="dialog-button primary"
            type="button"
            @click="addContactFromMemberProfile"
          >
            <UserPlus :size="16" />
            {{ homeT("actions.addContact") }}
          </button>
          <button
            v-if="!useridsMatch(memberProfileTarget.userid, currentUserid)"
            class="dialog-button ghost"
            type="button"
            @click="startPrivateChatFromMemberProfile"
          >
            <MessageCircle :size="16" />
            {{ homeT("actions.message") }}
          </button>
          <button
            v-if="!useridsMatch(memberProfileTarget.userid, currentUserid) && (activeConversation?.type === 'group' || isContactUser(memberProfileTarget.userid))"
            class="dialog-button ghost"
            type="button"
            @click="openNicknameFromMemberProfile"
          >
            <Pencil :size="16" />
            {{ homeT("info.setNickname") }}
          </button>
        </div>
      </div>
    </el-dialog>

    <el-dialog v-model="passwordDialogVisible" :title="homeT('profile.changePassword')" width="420px" class="chat-dialog">
      <div class="dialog-form password-dialog-form">
        <label>{{ homeT("profile.currentPassword") }}</label>
        <input v-model="passwordForm.currentPassword" type="password" :placeholder="homeT('profile.currentPasswordPlaceholder')" />

        <label>{{ homeT("profile.newPassword") }}</label>
        <input v-model="passwordForm.newPassword" type="password" :placeholder="homeT('profile.newPasswordPlaceholder')" />

        <label>{{ homeT("profile.confirmNewPassword") }}</label>
        <input v-model="passwordForm.confirmPassword" type="password" :placeholder="homeT('profile.confirmNewPasswordPlaceholder')" />
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="passwordDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" @click="savePassword">
          {{ homeT("profile.changePassword") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="contactDialogVisible" :title="homeT('dialogs.addContactTitle')" width="460px" class="chat-dialog">
      <div class="dialog-form">
        <label>{{ homeT("profile.userid") }}</label>
        <div class="chip-input">
          <input
            v-model.trim="contactUserid"
            type="text"
            :placeholder="homeT('dialogs.addContactPlaceholder')"
            @keydown.enter.prevent="submitAddContact"
          />
          <button type="button" @click="submitAddContact">
            <UserPlus :size="16" />
          </button>
        </div>

        <div v-if="contactLookupLoading" class="list-state compact">{{ homeT("search.searching") }}</div>
        <div v-else-if="contactLookupUsers.length" class="lookup-list">
          <div v-for="user in contactLookupUsers" :key="user.userid" class="user-result">
            <div class="avatar-presence-wrap">
              <el-avatar :size="40" :src="user.avatar || undefined">
                {{ initials(user.fullname || user.userid) }}
              </el-avatar>
              <span
                v-if="shouldShowPresence(user)"
                class="presence-dot"
                :class="{ online: isUserOnline(user) }"
                :title="presenceLabel(user)"
              ></span>
            </div>
            <div class="user-result-main">
              <strong>{{ user.fullname || user.userid }}</strong>
              <span>{{ user.userid }}</span>
            </div>
            <button
              v-if="user.isContact"
              class="result-action ghost"
              type="button"
              @click="startDirectChat(user.userid)"
            >
              {{ homeT("actions.message") }}
            </button>
            <button
              v-else
              class="result-action"
              type="button"
              @click="addContactFromUser(user)"
            >
              {{ homeT("actions.add") }}
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="contactDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" @click="submitAddContact">
          {{ homeT("actions.addContact") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="groupDialogVisible" :title="homeT('dialogs.createGroupTitle')" width="480px" class="chat-dialog">
      <div class="dialog-form">
        <label>{{ homeT("dialogs.groupName") }}</label>
        <input v-model.trim="groupName" type="text" :placeholder="homeT('dialogs.groupNamePlaceholder')" />

        <label>{{ homeT("dialogs.addByUserid") }}</label>
        <div class="chip-input">
          <input
            v-model.trim="groupMemberInput"
            type="text"
            :placeholder="homeT('dialogs.useridPlaceholder')"
            @keydown.enter.prevent="addGroupMemberChip"
          />
          <button type="button" @click="addGroupMemberChip">
            <Plus :size="16" />
          </button>
        </div>

        <div v-if="groupMemberUserids.length" class="chip-list">
          <span v-for="userid in groupMemberUserids" :key="userid" class="chip">
            {{ userid }}
            <button type="button" @click="removeGroupMemberChip(userid)">
              <X :size="13" />
            </button>
          </span>
        </div>

        <div v-if="contacts.length" class="contact-picker">
          <label>{{ homeT("dialogs.pickFromContacts") }}</label>
          <div class="picker-list">
            <button
              v-for="contact in contacts"
              :key="contact.userid"
              :class="{ selected: useridsInclude(groupMemberUserids, contact.userid) }"
              type="button"
              @click="toggleGroupMember(contact.userid)"
            >
              <div class="avatar-presence-wrap">
                <el-avatar :size="28" :src="contact.avatar || undefined">
                  {{ initials(contact.fullname || contact.userid) }}
                </el-avatar>
                <span
                  v-if="shouldShowPresence(contact)"
                  class="presence-dot mini"
                  :class="{ online: isUserOnline(contact) }"
                  :title="presenceLabel(contact)"
                ></span>
              </div>
              <span>{{ contact.fullname || contact.userid }}</span>
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="groupDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" @click="createGroup">
          {{ homeT("actions.createGroup") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="addMemberDialogVisible" :title="homeT('dialogs.addMemberTitle')" width="420px" class="chat-dialog">
      <div class="dialog-form">
        <label>{{ homeT("dialogs.memberUserid") }}</label>
        <div class="chip-input">
          <input
            v-model.trim="addMemberInput"
            type="text"
            :placeholder="homeT('dialogs.useridPlaceholder')"
            @keydown.enter.prevent="addMemberChip"
          />
          <button type="button" @click="addMemberChip">
            <Plus :size="16" />
          </button>
        </div>

        <div v-if="addMemberUserids.length" class="chip-list">
          <span v-for="userid in addMemberUserids" :key="userid" class="chip">
            {{ userid }}
            <button type="button" @click="removeAddMemberChip(userid)">
              <X :size="13" />
            </button>
          </span>
        </div>

        <div v-if="contacts.length" class="contact-picker">
          <label>{{ homeT("dialogs.pickFromContacts") }}</label>
          <div class="picker-list">
            <button
              v-for="contact in contacts"
              :key="contact.userid"
              :class="{ selected: useridsInclude(addMemberUserids, contact.userid) }"
              type="button"
              @click="toggleAddMember(contact.userid)"
            >
              <div class="avatar-presence-wrap">
                <el-avatar :size="28" :src="contact.avatar || undefined">
                  {{ initials(contact.fullname || contact.userid) }}
                </el-avatar>
                <span
                  v-if="shouldShowPresence(contact)"
                  class="presence-dot mini"
                  :class="{ online: isUserOnline(contact) }"
                  :title="presenceLabel(contact)"
                ></span>
              </div>
              <span>{{ contact.fullname || contact.userid }}</span>
            </button>
          </div>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="addMemberDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" @click="submitAddMembers">
          {{ homeT("actions.add") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="nicknameDialogVisible" :title="homeT('dialogs.nicknameTitle')" width="420px" class="chat-dialog">
      <div class="dialog-form">
        <label>{{ homeT("dialogs.member") }}</label>
        <input :value="nicknameTarget?.fullname || nicknameTarget?.userid || ''" disabled type="text" />

        <label>{{ homeT("dialogs.nickname") }}</label>
        <input
          v-model.trim="nicknameValue"
          type="text"
          maxlength="80"
          :placeholder="homeT('dialogs.nicknamePlaceholder')"
          @keydown.enter.prevent="submitNickname"
        />
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="nicknameDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" @click="submitNickname">
          {{ homeT("actions.save") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="pollDialogVisible" :title="homeT('poll.createTitle')" width="480px" class="chat-dialog poll-dialog">
      <div class="dialog-form">
        <label>{{ homeT("poll.question") }}</label>
        <input
          v-model.trim="pollForm.question"
          type="text"
          maxlength="500"
          :placeholder="homeT('poll.questionPlaceholder')"
          @keydown.enter.prevent="submitPoll"
        />

        <label>{{ homeT("poll.options") }}</label>
        <div class="poll-option-editor">
          <div v-for="(_, index) in pollForm.options" :key="index" class="poll-option-input">
            <input
              v-model.trim="pollForm.options[index]"
              type="text"
              maxlength="160"
              :placeholder="homeT('poll.optionPlaceholder', { number: index + 1 })"
            />
            <button
              type="button"
              :disabled="pollForm.options.length <= 2"
              :aria-label="homeT('poll.removeOption')"
              @click="removePollOption(index)"
            >
              <X :size="15" />
            </button>
          </div>
          <button v-if="pollForm.options.length < 20" class="poll-add-option" type="button" @click="addPollOption">
            <Plus :size="15" />
            <span>{{ homeT("poll.addOption") }}</span>
          </button>
        </div>

        <div class="poll-settings">
          <label>
            <input v-model="pollForm.allowCustomOptions" type="checkbox" />
            <span>{{ homeT("poll.allowCustomOptions") }}</span>
          </label>
          <label>
            <input v-model="pollForm.allowMultiple" type="checkbox" />
            <span>{{ homeT("poll.allowMultiple") }}</span>
          </label>
          <label>
            <input v-model="pollForm.showVoters" type="checkbox" />
            <span>{{ homeT("poll.showVoters") }}</span>
          </label>
        </div>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="pollDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" :disabled="pollSubmitting" @click="submitPoll">
          {{ homeT("poll.create") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog v-model="reminderDialogVisible" :title="homeT('reminder.title')" width="500px" class="chat-dialog">
      <div class="dialog-form">
        <label>{{ homeT("reminder.content") }}</label>
        <input v-model.trim="reminderForm.title" maxlength="240" type="text" :placeholder="homeT('reminder.placeholder')" />
        <label>{{ homeT("reminder.time") }}</label>
        <input v-model="reminderForm.remindAt" type="datetime-local" />
        <label>{{ homeT("reminder.repeat") }}</label>
        <select v-model="reminderForm.repeatType">
          <option value="none">{{ homeT("reminder.repeat_none") }}</option>
          <option value="daily">{{ homeT("reminder.repeat_daily") }}</option>
          <option value="weekly">{{ homeT("reminder.repeat_weekly") }}</option>
          <option value="monthly">{{ homeT("reminder.repeat_monthly") }}</option>
        </select>
      </div>
      <div v-if="scheduledReminders.length" class="scheduled-reminder-list">
        <div v-for="reminder in scheduledReminders" :key="reminder.id">
          <AlarmClock :size="16" />
          <span>
            <strong>{{ reminder.title }}</strong>
            <small>{{ formatReminderTime(reminder.remindAt) }} · {{ reminderRepeatLabel(reminder.repeatType) }}</small>
          </span>
          <button v-if="reminder.creatorUserid === currentUserid" type="button" @click="cancelScheduledReminder(reminder)">
            <X :size="16" />
          </button>
        </div>
      </div>
      <p v-else class="muted reminder-empty">{{ homeT("reminder.empty") }}</p>
      <template #footer>
        <button class="dialog-button ghost" type="button" @click="reminderDialogVisible = false">{{ homeT("actions.cancel") }}</button>
        <button class="dialog-button primary" type="button" :disabled="reminderSubmitting" @click="submitReminder">{{ homeT("reminder.schedule") }}</button>
      </template>
    </el-dialog>

    <el-dialog v-model="forwardDialogVisible" :title="homeT('dialogs.forwardTitle')" width="440px" class="chat-dialog">
      <div class="forward-preview">
        <Forward :size="17" />
        <span>{{ forwardingMessage ? messageReferencePreview(forwardingMessage) : "" }}</span>
      </div>
      <div class="forward-conversation-list">
        <button
          v-for="conversation in conversations"
          :key="conversation.id"
          class="forward-conversation"
          :class="{ selected: forwardTargetConversationId === conversation.id }"
          type="button"
          @click="forwardTargetConversationId = conversation.id"
        >
          <el-avatar :size="34" :src="conversation.avatar || undefined">
            {{ initials(conversation.name) }}
          </el-avatar>
          <span>{{ conversation.name }}</span>
        </button>
      </div>

      <template #footer>
        <button class="dialog-button ghost" type="button" @click="forwardDialogVisible = false">
          {{ homeT("actions.cancel") }}
        </button>
        <button class="dialog-button primary" type="button" @click="submitForward">
          {{ homeT("actions.forward") }}
        </button>
      </template>
    </el-dialog>

    <el-dialog
      v-model="editHistoryDialogVisible"
      :title="homeT('chat.editHistory')"
      width="540px"
      class="chat-dialog edit-history-dialog"
    >
      <div v-if="editHistoryLoading" class="edit-history-state">
        {{ homeT("chat.loadingEditHistory") }}
      </div>
      <div v-else-if="!messageEditHistory.length" class="edit-history-state">
        {{ homeT("chat.noEditHistory") }}
      </div>
      <ol v-else class="edit-history-list">
        <li v-for="entry in messageEditHistory" :key="entry.auditId">
          <div class="edit-history-meta">
            <el-avatar :size="28" :src="entry.editorAvatar || undefined">
              {{ initials(entry.editorName) }}
            </el-avatar>
            <span>
              <strong>{{ entry.editorName || entry.editorUserid }}</strong>
              <small>{{ formatEditHistoryTime(entry.editedAt) }}</small>
            </span>
            <em>v{{ entry.previousVersion }} → v{{ entry.version }}</em>
          </div>
          <div class="edit-history-change">
            <p><small>{{ homeT("chat.beforeEdit") }}</small>{{ entry.previousContent }}</p>
            <p><small>{{ homeT("chat.afterEdit") }}</small>{{ entry.content }}</p>
          </div>
        </li>
      </ol>
    </el-dialog>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { ElMessage, ElMessageBox } from "element-plus";
import dayjs from "dayjs";
import BrandLogo from "@/components/BrandLogo.vue";
import {
  Archive,
  ArchiveRestore,
  AlarmClock,
  Bell,
  BellOff,
  Camera,
  CalendarClock,
  Check,
  CheckCheck,
  ChevronLeft,
  ChevronDown,
  ChevronUp,
  Copy,
  Download,
  File,
  FileArchive,
  FileAudio,
  FileCode,
  FileImage,
  FileSpreadsheet,
  FileText,
  FileVideo,
  Folder,
  FolderUp,
  Forward,
  History,
  Info,
  KeyRound,
  Link2,
  ListChecks,
  Languages,
  LogOut,
  MessageCircle,
  Mic,
  MicOff,
  MoreHorizontal,
  Paperclip,
  Pencil,
  Pin,
  Phone,
  PhoneCall,
  PhoneIncoming,
  PhoneMissed,
  PhoneOff,
  PhoneOutgoing,
  Plus,
  Presentation,
  Reply,
  RefreshCw,
  Search,
  SendHorizontal,
  SmilePlus,
  Square,
  Trash2,
  UploadCloud,
  Undo2,
  UserPlus,
  UserRound,
  Users,
  Video,
  VideoOff,
  X,
} from "lucide-vue-next";
import chatApi from "@/store/chat";
import {
  applyMessageReceipt,
  attachClientMessageId,
  canTransitionCallState,
  createClientMessageId,
  isRetryableSendError,
  mergeCatchUpCursor,
  messageClientId,
  messageDedupeKey,
  messageDeliveryState,
  messageSequence,
  normalizeReactionGroups,
  normalizeRealtimeEvent,
  shouldMarkReadForVisibility,
  seedMissingConversationCursors,
  snapshotCatchUpCursors,
} from "@/store/chatRuntime";

const router = useRouter();
const { t, locale } = useI18n();
const fallbackRefreshMs = 60 * 1000;
const normalizeUserid = (userid) => String(userid || "").trim();
const useridsMatch = (first, second) => {
  const normalizedFirst = normalizeUserid(first);
  const normalizedSecond = normalizeUserid(second);
  return normalizedFirst !== "" && normalizedFirst === normalizedSecond;
};
const hasUserid = (userid) => normalizeUserid(userid) !== "";
const isPersistedMessage = (message = {}) => Number.isFinite(Number(message.id)) && Number(message.id) > 0;
const useridsInclude = (userids = [], userid) => userids.some((item) => useridsMatch(item, userid));
const currentUserid = normalizeUserid(localStorage.getItem("userid"));
const currentUser = ref({
  userid: currentUserid,
  fullname: localStorage.getItem("fullname") || "",
  avatar: localStorage.getItem("avatar") || "",
});

const conversations = ref([]);
const contacts = ref([]);
const messages = ref([]);
const panelMode = ref("chats");
const contactSection = ref("friends");
const activeConversationId = ref(null);
const lastMessageIds = ref({});
const readState = ref({});
const unreadCounts = ref({});
const messageCursors = ref({});
const pendingMessages = ref({});
const typingUsers = ref({});
const reactionPending = ref({});
const editHistoryDialogVisible = ref(false);
const editHistoryLoading = ref(false);
const messageEditHistory = ref([]);
const settingsSaving = ref(false);
const toastNotifications = ref([]);
const loadingConversations = ref(false);
const loadingContacts = ref(false);
const loadingMessages = ref(false);
const loadingOlderMessages = ref(false);
const loadingInfoPanelHistory = ref(false);
const messagesHasMore = ref(false);
const sending = ref(false);
const uploading = ref(false);
const isDragging = ref(false);
const dragDepth = ref(0);
const searchKeyword = ref("");
const searchScope = ref("all");
const contactSearchKeyword = ref("");
const chatSearchResults = ref({ contacts: [], messages: [], files: [] });
const chatSearchUserResult = ref(null);
const searchingChat = ref(false);
const conversationSearchKeyword = ref("");
const conversationSearchIndex = ref(0);
const conversationSearchServerResults = ref([]);
const conversationSearchLoading = ref(false);
const showLatestButton = ref(false);
const newMessagesBelowCount = ref(0);
const composerText = ref("");
const mentionActive = ref(false);
const mentionQuery = ref("");
const mentionStartIndex = ref(-1);
const mentionSelectedIndex = ref(0);
const replyingTo = ref(null);
const forwardDialogVisible = ref(false);
const forwardingMessage = ref(null);
const forwardTargetConversationId = ref(null);
const pollDialogVisible = ref(false);
const pollSubmitting = ref(false);
const pollForm = ref({
  question: "",
  options: ["", ""],
  allowCustomOptions: false,
  allowMultiple: false,
  showVoters: true,
});
const pollVotingMessageIds = ref({});
const pollCustomInputs = ref({});
const reminderDialogVisible = ref(false);
const reminderSubmitting = ref(false);
const scheduledReminders = ref([]);
const reminderNotice = ref(null);
const reminderForm = ref({ title: "", remindAt: "", repeatType: "none" });
const pendingAttachments = ref([]);
const pendingAttachmentType = ref("file");
const isRecording = ref(false);
const preparingRecording = ref(false);
const recordingDuration = ref(0);
const groupDialogVisible = ref(false);
const groupName = ref("");
const groupMemberInput = ref("");
const groupMemberUserids = ref([]);
const membersExpanded = ref(false);
const addMemberDialogVisible = ref(false);
const addMemberInput = ref("");
const addMemberUserids = ref([]);
const nicknameDialogVisible = ref(false);
const nicknameTarget = ref(null);
const nicknameValue = ref("");
const nicknameScope = ref("group");
const contactDialogVisible = ref(false);
const contactUserid = ref("");
const contactLookupUsers = ref([]);
const contactLookupLoading = ref(false);
const profileDialogVisible = ref(false);
const memberProfileDialogVisible = ref(false);
const memberProfileTarget = ref(null);
const passwordDialogVisible = ref(false);
const infoPanelOpen = ref(false);
const infoPanelView = ref("details");
const storageTab = ref("media");
const profileForm = ref({ userid: currentUserid, fullname: "", avatar: "" });
const passwordForm = ref({ currentPassword: "", newPassword: "", confirmPassword: "" });
const messageListRef = ref(null);
const composerInputRef = ref(null);
const fileInputRef = ref(null);
const folderInputRef = ref(null);
const avatarInputRef = ref(null);
const groupAvatarInputRef = ref(null);
const groupBackgroundInputRef = ref(null);
const remoteAudioRef = ref(null);
const remoteVideoRef = ref(null);
const localVideoRef = ref(null);
const callState = ref("idle");
const currentCall = ref(null);
const callMuted = ref(false);
const callCameraOff = ref(false);
const callDuration = ref(0);
const realtimeStatus = ref("idle");
const realtimeLastError = ref("");
const realtimeLastUrl = ref("");
let refreshTimer = null;
let searchTimer = null;
let contactLookupTimer = null;
let realtimeSocket = null;
let realtimeReconnectTimer = null;
let realtimeStableTimer = null;
let realtimeReadyWaiters = [];
let realtimeHasConnected = false;
let realtimeReconnectAttempt = 0;
let realtimeConnecting = false;
let realtimeConnectionEpoch = 0;
let readAckTimer = null;
let typingStopTimer = null;
let typingLastSentAt = 0;
let typingConversationId = null;
let conversationSearchTimer = null;
let reminderNoticeTimer = null;
let reminderRingtoneContext = null;
let reminderRingtoneTimer = null;
let backgroundSyncPromise = null;
let searchRequestId = 0;
let conversationSearchRequestId = 0;
let contactLookupRequestId = 0;
let componentUnmounted = false;
let mediaRecorder = null;
let recordingStream = null;
let recordingChunks = [];
let recordingTimer = null;
let recordingStartedAt = 0;
let peerConnection = null;
let localCallStream = null;
let remoteCallStream = null;
let pendingCallIceCandidates = [];
let callTimeoutTimer = null;
let cachedIceServers = [];
let iceServersExpireAt = 0;
const realtimeBaseDelayMs = 1000;
const realtimeMaxDelayMs = 30000;
const realtimeStableAfterMs = 30000;
const currentDeviceId = chatApi.getOrCreateDeviceId();
let callDurationTimer = null;
let callStartedAt = 0;
let ringtoneContext = null;
let ringtoneTimer = null;
let discardRecording = false;
const readStateStorageKey = `ys_chat_read_state_${currentUserid}`;
const unreadStorageKey = `ys_chat_unread_counts_${currentUserid}`;
const messageCursorStorageKey = `ys_chat_message_cursors_${currentUserid}`;
const pendingMessagesStorageKey = `ys_chat_pending_messages_${currentUserid}`;
const seenRealtimeEventIds = new Set();
const typingExpiryTimers = new Map();
const deliveredAckMessageIds = new Set();
const deliveredHighWaterByConversation = new Map();
const readAckByConversation = new Map();

const languageOptions = [
  { value: "vi", label: "Tiếng Việt", short: "VI" },
  { value: "en", label: "English", short: "EN" },
  { value: "cn", label: "中文", short: "简" },
];

const searchScopeOptions = [
  { value: "all", labelKey: "search.scopes.all" },
  { value: "contacts", labelKey: "search.scopes.contacts" },
  { value: "messages", labelKey: "search.scopes.messages" },
  { value: "files", labelKey: "search.scopes.files" },
];
const searchPreviewLimit = 3;
const sharedPreviewLimit = 12;
const messagePageSize = 50;
const allMentionLabel = "All";
const allMentionOption = {
  userid: "__all__",
  fullname: allMentionLabel,
  mentionAll: true,
};
let messageRequestId = 0;
const storageTabs = [
  { value: "media", labelKey: "info.media" },
  { value: "files", labelKey: "info.files" },
  { value: "links", labelKey: "info.links" },
  { value: "polls", labelKey: "info.polls" },
];

const homeT = (key, params) => t(`home.${key}`, params);
const sortLocale = computed(() => (locale.value === "cn" ? "zh-Hans" : locale.value));
const currentLangCode = computed(() =>
  languageOptions.find((language) => language.value === locale.value)?.short || "VI",
);

const changeLocale = (lang) => {
  if (!languageOptions.some((language) => language.value === lang)) return;
  locale.value = lang;
  localStorage.setItem("locale", lang);
};

const activeConversation = computed(() =>
  conversations.value.find((conversation) => conversation.id === activeConversationId.value),
);
const activePinnedMessages = computed(() => {
  const pinned = activeConversation.value?.pinnedMessages;
  if (Array.isArray(pinned) && pinned.length) return pinned;
  return activeConversation.value?.pinnedMessage ? [activeConversation.value.pinnedMessage] : [];
});
const activePinnedMessage = computed(() => activePinnedMessages.value[0] || null);
const canStartAudioCall = computed(() => activeConversation.value?.type === "direct" && callState.value === "idle");
const isVideoCall = computed(() => currentCall.value?.mediaType === "video");
const callPeerName = computed(() => currentCall.value?.peerName || activeConversation.value?.name || "");
const callStatusLabel = computed(() => {
  if (callState.value === "incoming") return callText("incoming");
  if (callState.value === "outgoing") return callText("outgoing");
  if (callState.value === "connecting") return callText("connecting");
  if (callState.value === "active") return `${callText("active")} ${formatDuration(callDuration.value)}`;
  return "";
});

const panelTitle = computed(() => (panelMode.value === "contacts" ? homeT("rail.contacts") : homeT("rail.chats")));

const hasSearchKeyword = computed(() => searchKeyword.value.trim().length > 0);
const isAllSearchScope = computed(() => searchScope.value === "all");

const filteredConversations = computed(() => {
  const keyword = searchKeyword.value.trim().toLowerCase();
  if (!keyword) return conversations.value;
  return conversations.value.filter((conversation) => {
    const memberText = (conversation.members || [])
      .map((member) => `${member.fullname} ${member.nickname || ""} ${member.userid}`)
      .join(" ")
      .toLowerCase();
    return `${conversation.name} ${memberText}`.toLowerCase().includes(keyword);
  });
});

const hasPanelSearchText = computed(() =>
  panelMode.value === "contacts"
    ? contactSearchKeyword.value.trim().length > 0
    : searchKeyword.value.trim().length > 0,
);

const chatSearchContacts = computed(() => chatSearchResults.value.contacts || []);
const chatSearchMessages = computed(() => chatSearchResults.value.messages || []);
const chatSearchFiles = computed(() => {
  const keyword = normalizeDirectoryText(searchKeyword.value);
  return (chatSearchResults.value.files || []).flatMap((message) =>
    (message.attachments || [])
      .filter((attachment) => {
        if (!keyword) return true;
        return normalizeDirectoryText(`${attachment.fileName} ${attachment.relativePath}`).includes(keyword);
      })
      .map((attachment) => ({ message, attachment })),
  );
});
const searchPreviewItems = (items) => (isAllSearchScope.value ? items.slice(0, searchPreviewLimit) : items);
const visibleFilteredConversations = computed(() => searchPreviewItems(filteredConversations.value));
const visibleChatSearchContacts = computed(() => searchPreviewItems(chatSearchContacts.value));
const visibleChatSearchMessages = computed(() => searchPreviewItems(chatSearchMessages.value));
const visibleChatSearchFiles = computed(() => searchPreviewItems(chatSearchFiles.value));

const hasVisibleSearchResults = computed(() => {
  if (shouldShowSearchSection("contacts") && (filteredConversations.value.length || chatSearchContacts.value.length)) {
    if (searchScope.value !== "all") return filteredConversations.value.length > 0 || chatSearchContacts.value.length > 0;
    return true;
  }
  if (shouldShowSearchSection("contacts") && chatSearchUserResult.value) return true;
  if (shouldShowSearchSection("messages") && chatSearchMessages.value.length) return true;
  if (shouldShowSearchSection("files") && chatSearchFiles.value.length) return true;
  return false;
});

const conversationSearchMatches = computed(() => {
  const keyword = normalizeDirectoryText(conversationSearchKeyword.value);
  if (!keyword) return [];
  const localMatches = messages.value.filter((message) => messageMatchesKeyword(message, keyword));
  return mergeMessageLists(localMatches, conversationSearchServerResults.value);
});

const currentConversationSearchMessageId = computed(() =>
  conversationSearchMatches.value[conversationSearchIndex.value]?.id || 0,
);

const conversationSearchPositionLabel = computed(() => {
  if (!conversationSearchKeyword.value.trim()) return "";
  const total = conversationSearchMatches.value.length;
  if (!total) return `0/0`;
  return `${conversationSearchIndex.value + 1}/${total}`;
});

const activeTypingUsers = computed(() => {
  const conversationId = String(activeConversationId.value || "");
  const now = Date.now();
  return Object.values(typingUsers.value[conversationId] || {})
    .filter((entry) => entry.expiresAt > now && !useridsMatch(entry.userid, currentUserid));
});

const typingIndicatorText = computed(() => {
  const names = activeTypingUsers.value.map((entry) => entry.name || entry.userid).filter(Boolean);
  if (!names.length) return "";
  if (names.length === 1) return homeT("chat.typingOne", { name: names[0] });
  return homeT("chat.typingMany", { count: names.length });
});

const directoryGroups = computed(() =>
  conversations.value
    .filter((conversation) => conversation.type === "group")
    .slice()
    .sort((first, second) => (first.name || "").localeCompare(second.name || "", sortLocale.value)),
);

const filteredDirectoryContacts = computed(() => {
  const keyword = normalizeDirectoryText(contactSearchKeyword.value);
  if (!keyword) return contacts.value;
  return contacts.value.filter((contact) =>
    normalizeDirectoryText(`${displayName(contact)} ${contact.userid}`).includes(keyword),
  );
});

const groupedDirectoryContacts = computed(() => {
  const groups = new Map();
  filteredDirectoryContacts.value.forEach((contact) => {
    const letter = directoryLetter(displayName(contact));
    if (!groups.has(letter)) groups.set(letter, []);
    groups.get(letter).push(contact);
  });

  return Array.from(groups, ([letter, items]) => ({ letter, items }));
});

const filteredDirectoryGroups = computed(() => {
  const keyword = normalizeDirectoryText(contactSearchKeyword.value);
  if (!keyword) return directoryGroups.value;
  return directoryGroups.value.filter((group) => {
    const memberText = (group.members || [])
      .map((member) => `${displayName(member)} ${member.userid}`)
      .join(" ");
    return normalizeDirectoryText(`${group.name} ${memberText}`).includes(keyword);
  });
});

const contactDirectoryTitle = computed(() =>
  contactSection.value === "groups" ? homeT("contacts.groupsList") : homeT("contacts.friendsList"),
);

const contactDirectoryCountLabel = computed(() => {
  if (contactSection.value === "groups") return homeT("contacts.countGroups", { count: filteredDirectoryGroups.value.length });
  return homeT("contacts.countFriends", { count: filteredDirectoryContacts.value.length });
});

const messageListStyle = computed(() => {
  const background = activeConversation.value?.background;
  if (!background) return {};
  return {
    backgroundImage: `url("${cssUrl(background)}")`,
  };
});

const sharedAttachments = computed(() =>
  messages.value.flatMap((message) => message.attachments || []).reverse(),
);

const allSharedMedia = computed(() =>
  sharedAttachments.value
    .filter((attachment) => isImageAttachment(attachment) || isVideoAttachment(attachment)),
);

const sharedMedia = computed(() => allSharedMedia.value.slice(0, sharedPreviewLimit));

const allSharedDocuments = computed(() =>
  sharedAttachments.value
    .filter((attachment) => !isImageAttachment(attachment) && !isVideoAttachment(attachment) && !isAudioAttachment(attachment)),
);

const sharedDocuments = computed(() => allSharedDocuments.value.slice(0, sharedPreviewLimit));

const allSharedLinks = computed(() =>
  messages.value
    .filter((message) => message.type === "link" && message.content)
    .slice()
    .reverse(),
);

const sharedLinks = computed(() => allSharedLinks.value.slice(0, sharedPreviewLimit));

const allSharedPolls = computed(() =>
  messages.value
    .filter((message) => message.type === "poll" && message.poll)
    .slice()
    .sort((first, second) => messageSortValue(second) - messageSortValue(first)),
);

const sharedPolls = computed(() => allSharedPolls.value.slice(0, sharedPreviewLimit));

const activeStorageGroups = computed(() => {
  if (storageTab.value === "media") return groupStorageItems(allSharedMedia.value, (item) => item.createdAt);
  if (storageTab.value === "files") return groupStorageItems(allSharedDocuments.value, (item) => item.createdAt);
  if (storageTab.value === "polls") return groupStorageItems(allSharedPolls.value, (item) => item.poll?.updatedAt || item.createdAt);
  return groupStorageItems(allSharedLinks.value, (item) => item.createdAt);
});

const activeStorageEmptyText = computed(() => {
  if (storageTab.value === "media") return homeT("info.noMedia");
  if (storageTab.value === "files") return homeT("info.noFiles");
  if (storageTab.value === "polls") return homeT("info.noPolls");
  return homeT("info.noLinks");
});

const openStorageView = (type) => {
  storageTab.value = type;
  infoPanelView.value = "storage";
};

const closeStorageView = () => {
  infoPanelView.value = "details";
};

const goToStoredMessage = async (message) => {
  if (!message?.id) return;
  infoPanelView.value = "details";
  await scrollToMessage(message.id);
};

const recordingDurationLabel = computed(() => formatDuration(recordingDuration.value));

const isCurrentUserGroupOwner = computed(() => {
  if (activeConversation.value?.type !== "group") return false;
  return (activeConversation.value.members || []).some(
    (member) => useridsMatch(member.userid, currentUserid) && member.role === "owner",
  );
});

const shouldShowPresence = (user = {}) => hasUserid(user.userid) && !useridsMatch(user.userid, currentUserid);
const isUserOnline = (user = {}) => Boolean(user.isOnline);
const presenceLabel = (user = {}) => homeT(isUserOnline(user) ? "presence.online" : "presence.offline");

const conversationPresenceUser = (conversation = {}) => {
  if (conversation.type !== "direct") return null;
  return (conversation.members || []).find((member) => !useridsMatch(member.userid, currentUserid)) || null;
};

const presenceUserByUserid = (userid) =>
  activeConversation.value?.members?.find((member) => useridsMatch(member.userid, userid)) || { userid, isOnline: false };

const applyPresence = (userid, isOnline) => {
  const targetUserid = normalizeUserid(userid);
  if (!targetUserid) return;

  const updateUser = (user) => (useridsMatch(user?.userid, targetUserid) ? { ...user, isOnline } : user);

  contacts.value = contacts.value.map(updateUser);
  chatSearchResults.value = {
    ...chatSearchResults.value,
    contacts: (chatSearchResults.value.contacts || []).map(updateUser),
  };
  contactLookupUsers.value = contactLookupUsers.value.map(updateUser);
  conversations.value = conversations.value.map((conversation) => ({
    ...conversation,
    members: (conversation.members || []).map(updateUser),
  }));
};

const mentionSuggestions = computed(() => {
  if (!activeConversation.value || !mentionActive.value) return [];
  const keyword = mentionQuery.value.trim().toLowerCase();
  const members = activeConversation.value.members || [];
  const allOption = isGroupConversation(activeConversation.value) && mentionOptionMatches(allMentionOption, keyword)
    ? [allMentionOption]
    : [];
  const memberOptions = members
    .filter((member) => {
      return mentionOptionMatches(member, keyword);
    });

  return [...allOption, ...memberOptions];
});

const isGroupConversation = (conversation = {}) => conversation.type === "group";

const isAllMentionOption = (option = {}) => Boolean(option.mentionAll);

const mentionOptionKey = (option = {}) => (isAllMentionOption(option) ? "mention-all" : option.userid);

const mentionOptionName = (option = {}) => (isAllMentionOption(option) ? allMentionLabel : displayName(option));

const mentionOptionDetail = (option = {}) => (isAllMentionOption(option) ? "@All" : option.userid);

const mentionOptionMatches = (option = {}, keyword = "") => {
  if (!keyword) return true;
  return `${mentionOptionName(option)} ${option.fullname || ""} ${option.nickname || ""} ${option.userid || ""}`
    .toLowerCase()
    .includes(keyword);
};

onMounted(async () => {
  readState.value = loadStoredObject(readStateStorageKey);
  unreadCounts.value = loadStoredObject(unreadStorageKey);
  messageCursors.value = loadStoredObject(messageCursorStorageKey);
  pendingMessages.value = loadStoredObject(pendingMessagesStorageKey);
  await loadProfile();
  await loadContacts();
  await loadConversations(false);
  messageCursors.value = seedMissingConversationCursors(conversations.value, messageCursors.value);
  persistMessageCursors();
  connectRealtime();
  document.addEventListener("visibilitychange", syncAfterVisibilityReturn);
  window.addEventListener("online", syncAfterNetworkReturn);
  window.addEventListener("offline", syncAfterNetworkLost);
});

onBeforeUnmount(() => {
  componentUnmounted = true;
  stopFallbackRefresh();
  if (searchTimer) window.clearTimeout(searchTimer);
  if (contactLookupTimer) window.clearTimeout(contactLookupTimer);
  if (conversationSearchTimer) window.clearTimeout(conversationSearchTimer);
  if (reminderNoticeTimer) window.clearTimeout(reminderNoticeTimer);
  stopReminderRingtone();
  if (readAckTimer) window.clearTimeout(readAckTimer);
  stopLocalTyping(true);
  typingExpiryTimers.forEach((timer) => window.clearTimeout(timer));
  typingExpiryTimers.clear();
  document.removeEventListener("visibilitychange", syncAfterVisibilityReturn);
  window.removeEventListener("online", syncAfterNetworkReturn);
  window.removeEventListener("offline", syncAfterNetworkLost);
  cancelVoiceRecording();
  cleanupCall();
  disconnectRealtime();
});

watch([searchKeyword, searchScope], ([value, scope]) => {
  if (searchTimer) window.clearTimeout(searchTimer);
  const keyword = value.trim();
  if (!keyword) {
    searchRequestId += 1;
    chatSearchResults.value = { contacts: [], messages: [], files: [] };
    chatSearchUserResult.value = null;
    searchingChat.value = false;
    if (scope !== "all") searchScope.value = "all";
    return;
  }

  searchingChat.value = true;
  searchTimer = window.setTimeout(() => searchChatRealtime(keyword, scope), 250);
});

watch(conversationSearchKeyword, async (value) => {
  if (conversationSearchTimer) window.clearTimeout(conversationSearchTimer);
  conversationSearchIndex.value = 0;
  conversationSearchServerResults.value = [];
  const keyword = value.trim();
  if (keyword && activeConversationId.value) {
    conversationSearchTimer = window.setTimeout(() => {
      void searchActiveConversation(keyword, activeConversationId.value);
    }, 300);
  }
  await nextTick();
  if (currentConversationSearchMessageId.value) {
    await scrollToMessage(currentConversationSearchMessageId.value);
  }
});

watch(conversationSearchMatches, (matches) => {
  if (conversationSearchIndex.value >= matches.length) {
    conversationSearchIndex.value = Math.max(0, matches.length - 1);
  }
});

watch(activeConversationId, (nextConversationId, previousConversationId) => {
  if (previousConversationId && previousConversationId !== nextConversationId) {
    stopLocalTyping(true, previousConversationId);
  }
  conversationSearchKeyword.value = "";
  conversationSearchServerResults.value = [];
  conversationSearchIndex.value = 0;
  infoPanelView.value = "details";
  showLatestButton.value = false;
  newMessagesBelowCount.value = 0;
  scheduledReminders.value = [];
  reminderDialogVisible.value = false;
});

watch(contactUserid, (value) => {
  if (contactLookupTimer) window.clearTimeout(contactLookupTimer);
  const keyword = value.trim();
  if (!keyword) {
    contactLookupUsers.value = [];
    contactLookupLoading.value = false;
    return;
  }

  contactLookupLoading.value = true;
  contactLookupTimer = window.setTimeout(() => searchContactLookup(keyword), 250);
});

const loadStoredObject = (key) => {
  try {
    return JSON.parse(localStorage.getItem(key) || "{}");
  } catch {
    return {};
  }
};

const persistReadState = () => {
  localStorage.setItem(readStateStorageKey, JSON.stringify(readState.value));
};

const persistUnreadCounts = () => {
  localStorage.setItem(unreadStorageKey, JSON.stringify(unreadCounts.value));
};

const persistMessageCursors = () => {
  localStorage.setItem(messageCursorStorageKey, JSON.stringify(messageCursors.value));
};

const persistPendingMessages = () => {
  localStorage.setItem(pendingMessagesStorageKey, JSON.stringify(pendingMessages.value));
};

const unreadCount = (conversationId) => {
  const conversation = conversations.value.find((item) => item.id === conversationId);
  if (conversation && Object.prototype.hasOwnProperty.call(conversation, "unreadCount")) {
    return Number(conversation.unreadCount || 0);
  }
  return Number(unreadCounts.value[conversationId] || 0);
};

const formatUnreadCount = (conversationId) => {
  const count = unreadCount(conversationId);
  if (count > 99) return "99+";
  return String(count);
};

const isDocumentVisible = () => shouldMarkReadForVisibility(
  typeof document === "undefined" ? undefined : document.visibilityState,
);

const markConversationRead = (conversationId) => {
  if (!isDocumentVisible()) return;
  const conversation = conversations.value.find((item) => item.id === conversationId);
  const latestVisibleMessage = messages.value
    .filter((message) => message.conversationId === conversationId && isPersistedMessage(message))
    .at(-1);
  const lastMessageID = latestVisibleMessage?.id || conversation?.lastMessage?.id || lastMessageIds.value[conversationId] || 0;
  unreadCounts.value = { ...unreadCounts.value, [conversationId]: 0 };
  readState.value = { ...readState.value, [conversationId]: lastMessageID };
  conversations.value = conversations.value.map((item) => (
    item.id === conversationId ? { ...item, unreadCount: 0, lastReadMessageId: lastMessageID } : item
  ));
  persistUnreadCounts();
  persistReadState();
  if (Number(lastMessageID) > 0) scheduleReadAck(conversationId, lastMessageID);
};

const scheduleReadAck = (conversationId, messageId) => {
  const previous = Number(readAckByConversation.get(conversationId) || 0);
  if (Number(messageId) <= previous) return;
  readAckByConversation.set(conversationId, Number(messageId));
  if (readAckTimer) window.clearTimeout(readAckTimer);
  readAckTimer = window.setTimeout(flushReadAcks, 120);
};

const flushReadAcks = async () => {
  if (readAckTimer) window.clearTimeout(readAckTimer);
  readAckTimer = null;
  if (!isDocumentVisible()) return;
  const pending = Array.from(readAckByConversation.entries());
  readAckByConversation.clear();
  await Promise.allSettled(pending.map(async ([conversationId, messageId]) => {
    try {
      const res = await chatApi.markConversationRead(conversationId, messageId);
      applyConversationReadState(conversationId, res.data?.readState || res.data);
    } catch {
      const queued = Number(readAckByConversation.get(conversationId) || 0);
      readAckByConversation.set(conversationId, Math.max(queued, Number(messageId)));
    }
  }));
  if (readAckByConversation.size && !componentUnmounted && isDocumentVisible()) {
    readAckTimer = window.setTimeout(flushReadAcks, 1500);
  }
};

const applyConversationReadState = (conversationId, state = {}) => {
  if (!conversationId) return;
  const lastReadMessageId = Number(state.lastReadMessageId || state.last_read_message_id || 0);
  const unread = Number(state.unreadCount ?? state.unread_count ?? 0);
  conversations.value = conversations.value.map((conversation) => (
    conversation.id === conversationId
      ? { ...conversation, unreadCount: unread, lastReadMessageId: lastReadMessageId || conversation.lastReadMessageId }
      : conversation
  ));
  unreadCounts.value = { ...unreadCounts.value, [conversationId]: unread };
  if (lastReadMessageId) readState.value = { ...readState.value, [conversationId]: lastReadMessageId };
  persistUnreadCounts();
  persistReadState();
};

const handleConversationNotifications = (nextConversations, isInitialLoad) => {
  const nextLastMessageIds = {};

  nextConversations.forEach((conversation) => {
    const lastMessage = conversation.lastMessage;
    if (!lastMessage?.id) return;

    const conversationId = conversation.id;
    const previousLastMessageId = lastMessageIds.value[conversationId];
    const serverLastReadMessageId = Number(conversation.lastReadMessageId || conversation.readState?.lastReadMessageId || 0);
    const lastReadMessageId = serverLastReadMessageId || Number(readState.value[conversationId] || 0);
    const isNewMessage = previousLastMessageId && lastMessage.id !== previousLastMessageId;
    const isUnreadFromStorage = isInitialLoad && lastReadMessageId > 0 && lastMessage.id > lastReadMessageId;
    const fromOtherUser = lastMessage.type !== "system" && !useridsMatch(lastMessage.senderUserid, currentUserid);
    const isActiveConversation = conversationId === activeConversationId.value;

    const hasServerUnread = Object.prototype.hasOwnProperty.call(conversation, "unreadCount");
    if (hasServerUnread) {
      unreadCounts.value = { ...unreadCounts.value, [conversationId]: Number(conversation.unreadCount || 0) };
    }
    if (serverLastReadMessageId) {
      readState.value = { ...readState.value, [conversationId]: serverLastReadMessageId };
    }

    if (fromOtherUser && (isNewMessage || isUnreadFromStorage)) {
      if (!isActiveConversation && !hasServerUnread) {
        unreadCounts.value = {
          ...unreadCounts.value,
          [conversationId]: Math.max(1, unreadCount(conversationId) + (isNewMessage ? 1 : 0)),
        };
      }

      if (isNewMessage) {
        pushMessageNotification(conversation, lastMessage);
      }
    }

    nextLastMessageIds[conversationId] = lastMessage.id;
  });

  lastMessageIds.value = nextLastMessageIds;
  persistUnreadCounts();
  persistReadState();
};

const pushMessageNotification = (conversation, message) => {
  const id = `${conversation.id}-${message.id}-${Date.now()}`;
  const body = notificationPreview(message);
  toastNotifications.value = [
    {
      id,
      conversationId: conversation.id,
      title: conversation.name,
      avatar: conversation.avatar,
      body,
    },
    ...toastNotifications.value,
  ].slice(0, 4);

  window.setTimeout(() => dismissNotification(id), 6500);
};

const dismissNotification = (id) => {
  toastNotifications.value = toastNotifications.value.filter((item) => item.id !== id);
};

const openNotification = async (notification) => {
  dismissNotification(notification.id);
  const conversation = conversations.value.find((item) => item.id === notification.conversationId);
  if (conversation) {
    await selectConversation(conversation);
  }
};

const notificationPreview = (message) => {
  if (message.type === "system") return message.content || homeT("previews.system");
  const sender = message.senderName ? `${message.senderName}: ` : "";
  if (message.type === "voice") return `${sender}${homeT("previews.voice")}`;
  if (message.type === "file") return `${sender}${homeT("previews.sentFile")}`;
  if (message.type === "folder") return `${sender}${homeT("previews.sentFolder")}`;
  if (message.type === "link") return `${sender}${homeT("previews.sentLink")}`;
  if (message.type === "poll") return `${sender}${message.content || homeT("previews.poll")}`;
  return `${sender}${message.content || homeT("previews.newMessage")}`;
};

const formatReminderTime = (value) => dayjs(value).format("DD/MM/YYYY HH:mm");

const reminderRepeatLabel = (value) => homeT(`reminder.repeat_${value || "none"}`);

const openReminderDialog = async () => {
  if (!activeConversationId.value) return;
  const conversationId = activeConversationId.value;
  reminderForm.value = {
    title: "",
    remindAt: dayjs().add(1, "hour").format("YYYY-MM-DDTHH:mm"),
    repeatType: "none",
  };
  reminderDialogVisible.value = true;
  try {
    const response = await chatApi.getReminders(conversationId);
    if (Number(activeConversationId.value) !== Number(conversationId)) return;
    scheduledReminders.value = response.data?.reminders || [];
  } catch (error) {
    showApiError(error);
  }
};

const submitReminder = async () => {
  const title = reminderForm.value.title.trim();
  const remindAt = new Date(reminderForm.value.remindAt);
  if (!title || Number.isNaN(remindAt.getTime()) || remindAt <= new Date()) {
    ElMessage.warning(homeT("reminder.invalid"));
    return;
  }
  try {
    reminderSubmitting.value = true;
    const response = await chatApi.createReminder(activeConversationId.value, {
      title,
      remindAt: remindAt.toISOString(),
      repeatType: reminderForm.value.repeatType || "none",
    });
    const reminder = response.data?.reminder;
    if (reminder) {
      scheduledReminders.value = [...scheduledReminders.value.filter((item) => item.id !== reminder.id), reminder]
        .sort((first, second) => new Date(first.remindAt) - new Date(second.remindAt));
    }
    reminderForm.value.title = "";
    ElMessage.success(homeT("reminder.scheduled"));
  } catch (error) {
    showApiError(error);
  } finally {
    reminderSubmitting.value = false;
  }
};

const cancelScheduledReminder = async (reminder) => {
  try {
    await chatApi.cancelReminder(reminder.id);
    scheduledReminders.value = scheduledReminders.value.filter((item) => item.id !== reminder.id);
  } catch (error) {
    showApiError(error);
  }
};

const handleReminderRealtimeEvent = (event = {}) => {
  const reminder = event.payload || {};
  if (event.type === "reminder.canceled") {
    scheduledReminders.value = scheduledReminders.value.filter((item) => item.id !== Number(reminder.id));
    return;
  }
  if (event.type === "reminder.created" || event.type === "reminder.updated") {
    if (event.type === "reminder.created" && event.payload?.message?.id) {
      upsertMessage(event.payload.message);
    }
    if (Number(reminder.conversationId) === Number(activeConversationId.value)) {
      scheduledReminders.value = [...scheduledReminders.value.filter((item) => item.id !== reminder.id), reminder]
        .sort((first, second) => new Date(first.remindAt) - new Date(second.remindAt));
    }
    return;
  }
  scheduledReminders.value = scheduledReminders.value.filter((item) => item.id !== reminder.id);
  reminderNotice.value = reminder;
  startReminderRingtone();
  if (reminderNoticeTimer) window.clearTimeout(reminderNoticeTimer);
  reminderNoticeTimer = window.setTimeout(() => {
    if (reminderNotice.value?.id === reminder.id) dismissReminderNotice();
  }, 5000);
};

const connectRealtime = async () => {
  if (componentUnmounted || !localStorage.getItem("user_token") || realtimeConnecting) return;
  if (typeof navigator !== "undefined" && navigator.onLine === false) {
    realtimeStatus.value = "offline";
    return;
  }
  if (realtimeSocket?.readyState === WebSocket.OPEN || realtimeSocket?.readyState === WebSocket.CONNECTING) return;
  if (realtimeSocket) {
    realtimeSocket.onclose = null;
    realtimeSocket.onerror = null;
    realtimeSocket = null;
  }

  const epoch = ++realtimeConnectionEpoch;
  realtimeConnecting = true;
  const isReconnect = realtimeHasConnected;
  try {
    const response = await chatApi.issueRealtimeTicket(isReconnect);
    if (componentUnmounted || epoch !== realtimeConnectionEpoch) return;
    const ticket = String(response.data?.ticket || "");
    if (!ticket) throw new Error("Realtime ticket is empty");
    const socketUrl = chatApi.getRealtimeUrl(ticket, isReconnect);
    const displayUrl = new URL(socketUrl);
    displayUrl.search = "";
    realtimeLastUrl.value = displayUrl.toString();
    realtimeLastError.value = "";
    realtimeStatus.value = "connecting";
    realtimeSocket = new WebSocket(socketUrl);
  } catch (error) {
    if (epoch !== realtimeConnectionEpoch) return;
    realtimeStatus.value = "error";
    realtimeLastError.value = error?.message || "Cannot create WebSocket";
    settleRealtimeReadyWaiters(false);
    startFallbackRefresh();
    scheduleRealtimeReconnect();
    return;
  } finally {
    if (epoch === realtimeConnectionEpoch) realtimeConnecting = false;
  }

  realtimeSocket.onopen = () => {
    realtimeHasConnected = true;
    realtimeStatus.value = "connected";
    realtimeLastError.value = "";
    settleRealtimeReadyWaiters(true);
    stopFallbackRefresh();
    sendRealtimeEvent({
      type: "subscription.restore",
      eventId: createClientMessageId(),
      payload: { conversationIds: conversations.value.map((conversation) => conversation.id) },
    });
    if (realtimeStableTimer) window.clearTimeout(realtimeStableTimer);
    realtimeStableTimer = window.setTimeout(() => {
      realtimeReconnectAttempt = 0;
      realtimeStableTimer = null;
    }, realtimeStableAfterMs);
    void syncAfterRealtimeOpen(isReconnect);
  };

  realtimeSocket.onmessage = (event) => {
    try {
      handleRealtimeEvent(JSON.parse(event.data));
    } catch {
      // Ignore malformed realtime frames; reconnect and focused-window sync remain the fallback.
    }
  };

  realtimeSocket.onclose = () => {
    if (realtimeStableTimer) {
      window.clearTimeout(realtimeStableTimer);
      realtimeStableTimer = null;
    }
    realtimeSocket = null;
    realtimeStatus.value = "disconnected";
    settleRealtimeReadyWaiters(false);
    startFallbackRefresh();
    scheduleRealtimeReconnect();
  };

  realtimeSocket.onerror = () => {
    realtimeStatus.value = "error";
    realtimeLastError.value = "WebSocket error";
    realtimeSocket?.close();
  };
};

const scheduleRealtimeReconnect = () => {
  if (componentUnmounted || realtimeReconnectTimer || navigator.onLine === false) return;
  const cappedDelay = Math.min(realtimeMaxDelayMs, realtimeBaseDelayMs * (2 ** realtimeReconnectAttempt));
  const delay = Math.round((cappedDelay / 2) + (Math.random() * cappedDelay / 2));
  realtimeReconnectAttempt += 1;
  realtimeReconnectTimer = window.setTimeout(() => {
    realtimeReconnectTimer = null;
    void connectRealtime();
  }, delay);
};

const disconnectRealtime = () => {
	++realtimeConnectionEpoch;
	realtimeConnecting = false;
  if (realtimeReconnectTimer) {
    window.clearTimeout(realtimeReconnectTimer);
    realtimeReconnectTimer = null;
  }
  if (realtimeStableTimer) {
    window.clearTimeout(realtimeStableTimer);
    realtimeStableTimer = null;
  }
  settleRealtimeReadyWaiters(false);
  if (realtimeSocket) {
    const socket = realtimeSocket;
    realtimeSocket = null;
    socket.onclose = null;
    socket.close();
  }
};

const settleRealtimeReadyWaiters = (isReady) => {
  const waiters = realtimeReadyWaiters;
  realtimeReadyWaiters = [];
  waiters.forEach((resolve) => resolve(isReady));
};

const ensureRealtimeReady = async () => {
  if (realtimeSocket?.readyState === WebSocket.OPEN) return true;

  void connectRealtime();
  if (realtimeSocket?.readyState === WebSocket.OPEN) return true;

  return new Promise((resolve) => {
    const timeout = window.setTimeout(() => {
      realtimeReadyWaiters = realtimeReadyWaiters.filter((waiter) => waiter !== finish);
      resolve(false);
    }, 8000);

    const finish = (isReady) => {
      window.clearTimeout(timeout);
      resolve(isReady);
    };

    realtimeReadyWaiters.push(finish);
  });
};

const startFallbackRefresh = () => {
  if (componentUnmounted || refreshTimer) return;
  refreshTimer = window.setInterval(() => {
    void syncChatSnapshot();
  }, fallbackRefreshMs);
};

const stopFallbackRefresh = () => {
  if (!refreshTimer) return;
  window.clearInterval(refreshTimer);
  refreshTimer = null;
};

const syncChatSnapshot = async () => {
  if (backgroundSyncPromise) return backgroundSyncPromise;

  const cursorSnapshots = snapshotCatchUpCursors(conversations.value, messageCursors.value);
  const snapshottedIds = new Set(cursorSnapshots.map((item) => String(item.conversationId)));

  backgroundSyncPromise = (async () => {
    await catchUpAfterReconnect(cursorSnapshots);
    await loadConversations(false, { silent: true });
    const newConversationSnapshots = snapshotCatchUpCursors(conversations.value, messageCursors.value)
      .filter((item) => !snapshottedIds.has(String(item.conversationId)));
    if (newConversationSnapshots.length) await catchUpAfterReconnect(newConversationSnapshots);
  })().finally(() => {
    backgroundSyncPromise = null;
  });

  return backgroundSyncPromise;
};

const syncAfterRealtimeOpen = async (isReconnect) => {
  const catchUpSnapshots = isReconnect
    ? snapshotCatchUpCursors(conversations.value, messageCursors.value)
    : null;
  const snapshottedIds = new Set((catchUpSnapshots || []).map((item) => String(item.conversationId)));
  try {
    if (!conversations.value.length) await loadConversations(false, { silent: true });
    if (isReconnect) await catchUpAfterReconnect(catchUpSnapshots);
    await retryPendingMessages();
  } finally {
    await loadConversations(false, { silent: true });
    if (isReconnect) {
      const newConversationSnapshots = snapshotCatchUpCursors(conversations.value, messageCursors.value)
        .filter((item) => !snapshottedIds.has(String(item.conversationId)));
      if (newConversationSnapshots.length) await catchUpAfterReconnect(newConversationSnapshots);
    }
    if (activeConversationId.value && !isReconnect) {
      await loadMessages(activeConversationId.value, false);
    }
  }
};

const syncAfterVisibilityReturn = () => {
  if (!isDocumentVisible()) return;
  void connectRealtime();
  void (async () => {
    if (realtimeSocket?.readyState === WebSocket.OPEN) await catchUpAfterReconnect();
    await loadConversations(false, { silent: true });
    if (activeConversationId.value) markConversationRead(activeConversationId.value);
    if (readAckByConversation.size) await flushReadAcks();
    await reconcileCurrentCall();
  })();
};

const syncAfterNetworkReturn = () => {
  realtimeReconnectAttempt = 0;
  void connectRealtime();
  if (realtimeSocket?.readyState === WebSocket.OPEN) {
    void syncAfterRealtimeOpen(true);
  }
};

const syncAfterNetworkLost = () => {
  realtimeStatus.value = "offline";
  if (realtimeReconnectTimer) {
    window.clearTimeout(realtimeReconnectTimer);
    realtimeReconnectTimer = null;
  }
  if (realtimeSocket) realtimeSocket.close();
};

const handleRealtimeEvent = async (rawEvent) => {
  const event = normalizeRealtimeEvent(rawEvent);
  if (event.eventId) {
    if (seenRealtimeEventIds.has(event.eventId)) return;
    seenRealtimeEventIds.add(event.eventId);
    if (seenRealtimeEventIds.size > 1000) {
      const oldest = seenRealtimeEventIds.values().next().value;
      seenRealtimeEventIds.delete(oldest);
    }
  }

  if (isCallRealtimeEvent(event)) {
    await handleCallRealtimeEvent({ ...event, ...event.payload, type: event.type });
    return;
  }

  if (["reminder.created", "reminder.updated", "reminder.canceled", "reminder.due"].includes(event.type)) {
    handleReminderRealtimeEvent(event);
    return;
  }

  if (event.type === "chat.presence.changed" && event.userid) {
    applyPresence(event.userid, Boolean(event.isOnline));
    return;
  }

  if (event.type === "chat.poll.updated" && event.message?.id) {
    if (event.message.conversationId === activeConversationId.value) {
      upsertMessage(event.message);
      await scrollToBottom();
    }
    return;
  }

  if (["chat.message.created", "message.created"].includes(event.type) && event.message?.id) {
    const message = event.message;
    processReceivedMessages([message]);
    if (message.conversationId === activeConversationId.value) {
      const shouldStickToBottom = isMessageListNearBottom();
      upsertMessage(message);
      if (document.visibilityState === "visible") markConversationRead(message.conversationId);
      if (shouldStickToBottom) await scrollToBottom();
      else if (!isOwnMessage(message)) registerNewMessagesBelow(1);
    }
    await loadConversations(false, { silent: true });
    return;
  }

  if (["message.updated", "message.recalled"].includes(event.type) && event.message?.id) {
    if (event.message.conversationId === activeConversationId.value) upsertMessage(event.message);
    updateMessageCursor(event.message);
    await loadConversations(false, { silent: true });
    return;
  }

  if (event.type === "message.deleted" && event.messageId) {
    messages.value = messages.value.filter((message) => message.id !== event.messageId);
    return;
  }

  if (event.type === "reaction.updated") {
    applyReactionEvent(event);
    return;
  }

  if (event.type === "read.receipt") {
    applyReadReceipt(event);
    return;
  }

  if (event.type === "delivery.receipt") {
    applyDeliveryReceipt(event);
    return;
  }

  if (event.type === "typing.start" || event.type === "typing.stop") {
    applyTypingEvent(event);
    return;
  }

  if (event.type === "message.pinned" || event.type === "message.unpinned") {
    applyPinnedMessageEvent(event);
    return;
  }

  if (event.type === "conversation.settings.updated") {
    applyConversationSettingsEvent(event);
  }
};

const callText = (key) => ({
  start: "Gọi thoại",
  startVideo: "Gọi video",
  incomingVideo: "Cuộc gọi video đến",
  incoming: "Cuộc gọi đến",
  outgoing: "Đang gọi...",
  connecting: "Đang kết nối...",
  active: "Đang gọi",
  accept: "Nghe",
  reject: "Từ chối",
  end: "Kết thúc",
  mute: "Tắt micro",
  unmute: "Bật micro",
  cameraOn: "Bật camera",
  cameraOff: "Tắt camera",
  busy: "Người kia đang bận.",
  canceled: "Cuộc gọi đã hủy.",
  rejected: "Cuộc gọi bị từ chối.",
  ended: "Cuộc gọi đã kết thúc.",
  unavailable: "Trình duyệt này chưa hỗ trợ gọi thoại.",
  directOnly: "Chỉ hỗ trợ gọi trong chat cá nhân.",
  microphoneFailed: "Không thể truy cập micro.",
  cameraFailed: "Không thể truy cập camera.",
  websocketUnavailable: "Kết nối realtime chưa sẵn sàng.",
}[key] || key);

const realtimeUnavailableMessage = () => {
  const detail = [realtimeLastError.value, realtimeLastUrl.value].filter(Boolean).join(" - ");
  return detail ? `${callText("websocketUnavailable")} ${detail}` : callText("websocketUnavailable");
};

const isCallRealtimeEvent = (event = {}) => typeof event.type === "string" && event.type.startsWith("call.");

const directConversationPeer = (conversation = activeConversation.value) =>
  (conversation?.members || []).find((member) => !useridsMatch(member.userid, currentUserid)) || null;

const createCallId = (conversationId) =>
  `${conversationId}-${currentUserid || "user"}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

const transitionCallState = (nextState) => {
  if (!canTransitionCallState(callState.value, nextState)) return false;
  callState.value = nextState;
  return true;
};

const sendRealtimeEvent = (event) => {
  if (realtimeSocket?.readyState !== WebSocket.OPEN) {
    connectRealtime();
    return false;
  }
  realtimeSocket.send(JSON.stringify(event));
  return true;
};

const sendCallEvent = (type, signal = null, call = currentCall.value) => {
  if (!call?.id || !call.conversationId) return false;
  return sendRealtimeEvent({
    type,
    eventId: createClientMessageId(),
    conversationId: call.conversationId,
    callId: call.id,
    mediaType: call.mediaType || "audio",
    sourceDeviceId: currentDeviceId,
    signal,
  });
};

const loadWebrtcIceServers = async () => {
  if (cachedIceServers.length && Date.now() < iceServersExpireAt - 30000) return cachedIceServers;
  const response = await chatApi.getICEConfiguration();
  const servers = Array.isArray(response.data?.iceServers) ? response.data.iceServers : [];
  cachedIceServers = servers
    .filter((server) => server && (Array.isArray(server.urls) || typeof server.urls === "string"))
    .map((server) => ({
      urls: server.urls,
      ...(server.username ? { username: server.username } : {}),
      ...(server.credential ? { credential: server.credential } : {}),
    }));
  const expiresAt = Date.parse(response.data?.expiresAt || "");
  iceServersExpireAt = Number.isFinite(expiresAt) ? expiresAt : Date.now() + 5 * 60 * 1000;
  return cachedIceServers;
};

const sendCallControlEvent = async (type, call = currentCall.value) => {
  if (!call?.id || !call.conversationId) return false;
  try {
    await chatApi.sendCallControlEvent({
      type,
      conversationId: call.conversationId,
      callId: call.id,
      deviceId: currentDeviceId,
      mediaType: call.mediaType || "audio",
    });
    return true;
  } catch {
    return false;
  }
};

const prepareLocalCallMedia = async () => {
  if (localCallStream) return localCallStream;
  if (!window.isSecureContext) {
    const error = new Error("INSECURE_CONTEXT");
    error.name = "SecurityError";
    throw error;
  }
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error("WEBRTC_UNAVAILABLE");
  }
  localCallStream = await navigator.mediaDevices.getUserMedia({
    audio: {
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    },
    video: isVideoCall.value
      ? {
        facingMode: "user",
        width: { ideal: 1280 },
        height: { ideal: 720 },
      }
      : false,
  });
  callMuted.value = false;
  callCameraOff.value = false;
  await nextTick();
  if (localVideoRef.value) localVideoRef.value.srcObject = localCallStream;
  return localCallStream;
};

const callMediaErrorMessage = (error = {}) => {
  if (!window.isSecureContext) {
    return "Camera và micro chỉ hoạt động trên HTTPS hoặc localhost.";
  }
  if (!navigator.mediaDevices?.getUserMedia || error.message === "WEBRTC_UNAVAILABLE") {
    return callText("unavailable");
  }
  if (error.name === "NotAllowedError" || error.name === "SecurityError") {
    return isVideoCall.value
      ? "Quyền camera hoặc micro đang bị chặn. Hãy cho phép camera và microphone trên trình duyệt."
      : "Quyền micro đang bị chặn. Hãy cho phép microphone trên trình duyệt.";
  }
  if (error.name === "NotFoundError" || error.name === "DevicesNotFoundError") {
    return isVideoCall.value ? callText("cameraFailed") : callText("microphoneFailed");
  }
  if (error.name === "NotReadableError" || error.name === "TrackStartError") {
    return "Micro dang bi ung dung khac su dung hoac he thong dang chan.";
  }
  return callText("microphoneFailed");
};

const attachLocalCallStream = async () => {
  await nextTick();
  if (localVideoRef.value && localCallStream) {
    localVideoRef.value.srcObject = localCallStream;
  }
};

const attachRemoteCallStream = async () => {
  await nextTick();
  if (!remoteAudioRef.value || !remoteCallStream) return;
  if (remoteAudioRef.value.srcObject !== remoteCallStream) {
    remoteAudioRef.value.srcObject = remoteCallStream;
  }
  if (remoteVideoRef.value && remoteVideoRef.value.srcObject !== remoteCallStream) {
    remoteVideoRef.value.srcObject = remoteCallStream;
  }
  try {
    await remoteAudioRef.value.play();
  } catch {
    // Browsers can require a user gesture before audio starts.
  }
};

const addLocalCallTracks = () => {
  if (!peerConnection || !localCallStream) return;
  const existingTracks = new Set(peerConnection.getSenders().map((sender) => sender.track).filter(Boolean));
  localCallStream.getTracks().forEach((track) => {
    if (!existingTracks.has(track)) {
      peerConnection.addTrack(track, localCallStream);
    }
  });
};

const ensurePeerConnection = async () => {
  if (peerConnection) return peerConnection;

  remoteCallStream = new MediaStream();
  peerConnection = new RTCPeerConnection({ iceServers: await loadWebrtcIceServers() });
  addLocalCallTracks();

  peerConnection.onicecandidate = ({ candidate }) => {
    if (candidate) {
      sendCallEvent("call.ice", candidate.toJSON ? candidate.toJSON() : candidate);
    }
  };

  peerConnection.ontrack = (event) => {
    event.streams?.[0]?.getTracks().forEach((track) => {
      if (!remoteCallStream.getTracks().some((item) => item.id === track.id)) {
        remoteCallStream.addTrack(track);
      }
    });
    void attachRemoteCallStream();
    activateCall();
  };

  peerConnection.onconnectionstatechange = () => {
    const state = peerConnection?.connectionState;
    if (state === "connected") {
      activateCall();
    }
    if (state === "failed" || state === "closed") {
      cleanupCall();
    }
  };

  return peerConnection;
};

const flushPendingCallIceCandidates = async () => {
  if (!peerConnection?.remoteDescription || pendingCallIceCandidates.length === 0) return;
  const candidates = pendingCallIceCandidates;
  pendingCallIceCandidates = [];
  for (const candidate of candidates) {
    try {
      await peerConnection.addIceCandidate(new RTCIceCandidate(candidate));
    } catch {
      // Remote ICE can become stale if a call is ended while packets are still in flight.
    }
  }
};

const activateCall = () => {
  if (callState.value === "active") return;
  stopRingtone();
  if (callTimeoutTimer) {
    window.clearTimeout(callTimeoutTimer);
    callTimeoutTimer = null;
  }
  if (!transitionCallState("active")) return;
  callStartedAt = Date.now();
  callDuration.value = 0;
  if (callDurationTimer) window.clearInterval(callDurationTimer);
  callDurationTimer = window.setInterval(() => {
    callDuration.value = Math.floor((Date.now() - callStartedAt) / 1000);
  }, 1000);
};

const startCallTimeout = () => {
  if (callTimeoutTimer) window.clearTimeout(callTimeoutTimer);
  callTimeoutTimer = window.setTimeout(() => {
    if (callState.value === "incoming") {
      cleanupCall();
      return;
    }
    if (callState.value === "outgoing" || callState.value === "connecting") {
      void sendCallControlEvent("call.cancel");
      cleanupCall(callText("canceled"));
    }
  }, 45 * 1000);
};

const startRingtone = () => {
  stopRingtone();
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return;

  try {
    ringtoneContext = new AudioContextClass();
    const playTone = () => {
      if (!ringtoneContext) return;
      const oscillator = ringtoneContext.createOscillator();
      const gain = ringtoneContext.createGain();
      oscillator.type = "sine";
      oscillator.frequency.value = 880;
      gain.gain.setValueAtTime(0.0001, ringtoneContext.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.16, ringtoneContext.currentTime + 0.03);
      gain.gain.exponentialRampToValueAtTime(0.0001, ringtoneContext.currentTime + 0.38);
      oscillator.connect(gain);
      gain.connect(ringtoneContext.destination);
      oscillator.start();
      oscillator.stop(ringtoneContext.currentTime + 0.42);
    };
    void ringtoneContext.resume().then(playTone).catch(() => {});
    ringtoneTimer = window.setInterval(playTone, 1400);
  } catch {
    ringtoneContext = null;
  }
};

const stopRingtone = () => {
  if (ringtoneTimer) {
    window.clearInterval(ringtoneTimer);
    ringtoneTimer = null;
  }
  if (ringtoneContext) {
    void ringtoneContext.close().catch(() => {});
    ringtoneContext = null;
  }
};

const startReminderRingtone = () => {
  stopReminderRingtone();
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return;

  try {
    reminderRingtoneContext = new AudioContextClass();
    const playTone = () => {
      if (!reminderRingtoneContext) return;
      const oscillator = reminderRingtoneContext.createOscillator();
      const gain = reminderRingtoneContext.createGain();
      oscillator.type = "sine";
      oscillator.frequency.value = 880;
      gain.gain.setValueAtTime(0.0001, reminderRingtoneContext.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.14, reminderRingtoneContext.currentTime + 0.03);
      gain.gain.exponentialRampToValueAtTime(0.0001, reminderRingtoneContext.currentTime + 0.38);
      oscillator.connect(gain);
      gain.connect(reminderRingtoneContext.destination);
      oscillator.start();
      oscillator.stop(reminderRingtoneContext.currentTime + 0.42);
    };
    void reminderRingtoneContext.resume().then(playTone).catch(() => {});
    reminderRingtoneTimer = window.setInterval(playTone, 1400);
  } catch {
    reminderRingtoneContext = null;
  }
};

const stopReminderRingtone = () => {
  if (reminderRingtoneTimer) {
    window.clearInterval(reminderRingtoneTimer);
    reminderRingtoneTimer = null;
  }
  if (reminderRingtoneContext) {
    void reminderRingtoneContext.close().catch(() => {});
    reminderRingtoneContext = null;
  }
};

const dismissReminderNotice = () => {
  reminderNotice.value = null;
  if (reminderNoticeTimer) {
    window.clearTimeout(reminderNoticeTimer);
    reminderNoticeTimer = null;
  }
  stopReminderRingtone();
};

const notifyIncomingCall = (peerName) => {
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  try {
    new Notification(callText("incoming"), {
      body: peerName,
      tag: `ys-call-${currentCall.value?.id || ""}`,
      silent: false,
    });
  } catch {
    // Browser notifications are best-effort only.
  }
};

const requestNotificationPermission = () => {
  if (!("Notification" in window) || Notification.permission !== "default") return;
  void Notification.requestPermission().catch(() => {});
};

const startCall = async (mediaType = "audio") => {
  if (!activeConversation.value || activeConversation.value.type !== "direct") {
    ElMessage.warning(callText("directOnly"));
    return;
  }
  if (!canStartAudioCall.value) return;

  const peer = directConversationPeer(activeConversation.value);
  const call = {
    id: createCallId(activeConversation.value.id),
    conversationId: activeConversation.value.id,
    peerUserid: peer?.userid || "",
    peerName: activeConversation.value.name,
    direction: "outgoing",
    mediaType: mediaType === "video" ? "video" : "audio",
  };

  try {
    if (!(await ensureRealtimeReady())) {
      ElMessage.error(realtimeUnavailableMessage());
      return;
    }
    currentCall.value = call;
    await prepareLocalCallMedia();
    if (!transitionCallState("outgoing")) {
      cleanupCall();
      return;
    }
    await attachLocalCallStream();
    startRingtone();
    requestNotificationPermission();
    if (!(await sendCallControlEvent("call.invite", call))) {
      cleanupCall(callText("websocketUnavailable"));
      return;
    }
    startCallTimeout();
  } catch (error) {
    const mediaError = callMediaErrorMessage(error);
    cleanupCall();
    ElMessage.error(mediaError);
  }
};

const startAudioCall = () => startCall("audio");
const startVideoCall = () => startCall("video");

const acceptIncomingCall = async () => {
  if (callState.value !== "incoming" || !currentCall.value) return;
  stopRingtone();
  try {
    if (!(await ensureRealtimeReady())) {
      cleanupCall(realtimeUnavailableMessage());
      return;
    }
    if (!(await sendCallControlEvent("call.accept"))) {
      cleanupCall(callText("ended"));
      return;
    }
    if (!transitionCallState("connecting")) return;
    await prepareLocalCallMedia();
    await ensurePeerConnection();
    startCallTimeout();
  } catch (error) {
    const mediaError = callMediaErrorMessage(error);
    void sendCallControlEvent("call.end");
    cleanupCall();
    ElMessage.error(mediaError);
  }
};

const rejectIncomingCall = () => {
  if (callState.value !== "incoming") return;
  void sendCallControlEvent("call.reject");
  cleanupCall();
};

const endOrCancelCall = () => {
  if (!currentCall.value) return;
  if (callState.value === "outgoing" || callState.value === "connecting") {
    void sendCallControlEvent("call.cancel");
  } else {
    void sendCallControlEvent("call.end");
  }
  cleanupCall();
};

const toggleCallMute = () => {
  callMuted.value = !callMuted.value;
  localCallStream?.getAudioTracks().forEach((track) => {
    track.enabled = !callMuted.value;
  });
};

const toggleCallCamera = () => {
  if (!isVideoCall.value) return;
  callCameraOff.value = !callCameraOff.value;
  localCallStream?.getVideoTracks().forEach((track) => {
    track.enabled = !callCameraOff.value;
  });
};

const cleanupCall = (message = "") => {
  stopRingtone();
  if (callTimeoutTimer) {
    window.clearTimeout(callTimeoutTimer);
    callTimeoutTimer = null;
  }
  if (callDurationTimer) {
    window.clearInterval(callDurationTimer);
    callDurationTimer = null;
  }
  if (peerConnection) {
    peerConnection.onicecandidate = null;
    peerConnection.ontrack = null;
    peerConnection.onconnectionstatechange = null;
    peerConnection.close();
    peerConnection = null;
  }
  localCallStream?.getTracks().forEach((track) => track.stop());
  remoteCallStream?.getTracks().forEach((track) => track.stop());
  localCallStream = null;
  remoteCallStream = null;
  pendingCallIceCandidates = [];
  if (remoteAudioRef.value) {
    remoteAudioRef.value.srcObject = null;
  }
  if (remoteVideoRef.value) remoteVideoRef.value.srcObject = null;
  if (localVideoRef.value) localVideoRef.value.srcObject = null;
  currentCall.value = null;
  transitionCallState("idle");
  callMuted.value = false;
  callCameraOff.value = false;
  callDuration.value = 0;
  callStartedAt = 0;
  if (message) {
    ElMessage.info(message);
  }
};

const callMatchesEvent = (event = {}) =>
  currentCall.value
  && event.callId === currentCall.value.id
  && Number(event.conversationId) === Number(currentCall.value.conversationId);

const reconcileCurrentCall = async () => {
  const call = currentCall.value;
  if (!call?.id) return;
  try {
    const response = await chatApi.getCall(call.id);
    if (currentCall.value?.id !== call.id) return;
    const record = response.data?.call || {};
    const terminalStatuses = new Set(["rejected", "busy", "canceled", "completed", "missed", "failed"]);
    if (terminalStatuses.has(record.status)) {
      cleanupCall(callText("ended"));
      return;
    }
    if (callState.value === "incoming"
      && record.status !== "ringing"
      && record.acceptedByDeviceId !== currentDeviceId) {
      cleanupCall(callText("ended"));
    }
  } catch {
    // The local timeout and the next foreground sync remain fallbacks.
  }
};

const handleCallRealtimeEvent = async (event) => {
  if (event.sourceDeviceId && event.sourceDeviceId === currentDeviceId) return;

  if (event.type === "call.invite") {
    if (callState.value !== "idle") {
      void sendCallControlEvent("call.busy", {
        id: event.callId,
        conversationId: event.conversationId,
      });
      return;
    }

    const conversation = conversations.value.find((item) => item.id === event.conversationId);
    if (!conversation || conversation.type !== "direct") return;

    currentCall.value = {
      id: event.callId,
      conversationId: event.conversationId,
      peerUserid: event.fromUserid || event.userid || "",
      peerName: conversation.name,
      direction: "incoming",
      mediaType: event.mediaType === "video" ? "video" : "audio",
    };
    if (!transitionCallState("incoming")) {
      currentCall.value = null;
      return;
    }
    startRingtone();
    startCallTimeout();
    notifyIncomingCall(conversation.name);
    return;
  }

  if (!callMatchesEvent(event)) return;

  if (event.type === "call.accept") {
    if (useridsMatch(event.fromUserid || event.userid, currentUserid) && callState.value === "incoming") {
      cleanupCall(callText("ended"));
      return;
    }
    if (callState.value !== "outgoing") return;
    stopRingtone();
    if (!transitionCallState("connecting")) return;
    try {
      await prepareLocalCallMedia();
      const pc = await ensurePeerConnection();
      const offer = await pc.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: isVideoCall.value });
      await pc.setLocalDescription(offer);
      sendCallEvent("call.offer", pc.localDescription?.toJSON ? pc.localDescription.toJSON() : pc.localDescription);
      startCallTimeout();
    } catch (error) {
      void sendCallControlEvent("call.end");
      cleanupCall(callMediaErrorMessage(error));
    }
    return;
  }

  if (event.type === "call.reject") {
    cleanupCall(callText("rejected"));
    return;
  }

  if (event.type === "call.busy") {
    cleanupCall(callText("busy"));
    return;
  }

  if (event.type === "call.cancel") {
    cleanupCall(callText("canceled"));
    return;
  }

  if (event.type === "call.end") {
    cleanupCall(callText("ended"));
    return;
  }

  if (event.type === "call.offer" && event.signal) {
    try {
      if (callState.value === "incoming" && !transitionCallState("connecting")) return;
      await prepareLocalCallMedia();
      const pc = await ensurePeerConnection();
      await pc.setRemoteDescription(new RTCSessionDescription(event.signal));
      await flushPendingCallIceCandidates();
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      sendCallEvent("call.answer", pc.localDescription?.toJSON ? pc.localDescription.toJSON() : pc.localDescription);
    } catch {
      void sendCallControlEvent("call.end");
      cleanupCall();
    }
    return;
  }

  if (event.type === "call.answer" && event.signal) {
    try {
      if (!peerConnection) return;
      await peerConnection.setRemoteDescription(new RTCSessionDescription(event.signal));
      await flushPendingCallIceCandidates();
    } catch {
      cleanupCall();
    }
    return;
  }

  if (event.type === "call.ice" && event.signal) {
    if (!peerConnection?.remoteDescription) {
      pendingCallIceCandidates.push(event.signal);
      return;
    }
    try {
      await peerConnection.addIceCandidate(new RTCIceCandidate(event.signal));
    } catch {
      // Ignore stale ICE candidates after a call transition.
    }
  }
};

const openConversationById = async (conversationId) => {
  let conversation = conversations.value.find((item) => item.id === conversationId);
  if (!conversation) {
    await loadConversations(false);
    conversation = conversations.value.find((item) => item.id === conversationId);
  }
  if (conversation) {
    await selectConversation(conversation);
  }
};

const shouldShowSearchSection = (section) => searchScope.value === "all" || searchScope.value === section;

const clearPanelSearch = () => {
  if (panelMode.value === "contacts") {
    contactSearchKeyword.value = "";
    return;
  }
  searchKeyword.value = "";
  searchScope.value = "all";
  chatSearchResults.value = { contacts: [], messages: [], files: [] };
  chatSearchUserResult.value = null;
};

const clearConversationSearch = () => {
  conversationSearchKeyword.value = "";
  conversationSearchIndex.value = 0;
  conversationSearchServerResults.value = [];
};

const searchActiveConversation = async (keyword, conversationId) => {
  const requestId = ++conversationSearchRequestId;
  try {
    conversationSearchLoading.value = true;
    const res = await chatApi.searchConversationMessages(conversationId, { keyword, limit: 100 });
    if (
      requestId !== conversationSearchRequestId
      || conversationId !== activeConversationId.value
      || keyword !== conversationSearchKeyword.value.trim()
    ) return;
    conversationSearchServerResults.value = res.data?.messages || res.data?.results?.messages || [];
  } catch (error) {
    // Old servers did not expose scoped search; the already loaded messages remain searchable.
    if (error?.response?.status !== 404 && requestId === conversationSearchRequestId) showApiError(error);
  } finally {
    if (requestId === conversationSearchRequestId) conversationSearchLoading.value = false;
  }
};

const conversationNameById = (conversationId) =>
  conversations.value.find((conversation) => conversation.id === conversationId)?.name || homeT("search.conversation");

const messageSearchPreview = (message = {}) => message.content || messageReferencePreview(message);

const openSearchMessage = async (message) => {
  if (!message?.conversationId) return;
  await openConversationById(message.conversationId);
  if (!messages.value.some((item) => item.id === message.id)) {
    messages.value = [...messages.value, message].sort((first, second) => first.id - second.id);
  }
  await scrollToMessage(message.id);
};

const goToConversationSearchResult = async (direction) => {
  const matches = conversationSearchMatches.value;
  if (!matches.length) return;
  const nextIndex = (conversationSearchIndex.value + direction + matches.length) % matches.length;
  conversationSearchIndex.value = nextIndex;
  await scrollToMessage(matches[nextIndex].id);
};

const isConversationSearchMatch = (messageId) =>
  conversationSearchMatches.value.some((message) => message.id === messageId);

const messageMatchesKeyword = (message = {}, keyword) => {
  if (message.type === "call" || message.type === "system") return false;
  const text = normalizeDirectoryText(`${message.senderName} ${message.content}`);
  if (text.includes(keyword)) return true;
  return (message.attachments || []).some((attachment) =>
    normalizeDirectoryText(`${attachment.fileName} ${attachment.relativePath}`).includes(keyword),
  );
};

const setPanelMode = (mode) => {
  panelMode.value = mode;
  infoPanelOpen.value = false;
  if (mode === "contacts") {
    searchKeyword.value = "";
    loadContacts();
    loadConversations(false);
  } else {
    contactSearchKeyword.value = "";
  }
};

const isContactUser = (userid) => contacts.value.some((contact) => useridsMatch(contact.userid, userid));

const withContactState = (user) => ({
  ...user,
  isContact: Boolean(user.isContact) || isContactUser(user.userid),
});

const sortUsers = (users) =>
  [...users].sort((first, second) => {
    const firstName = (first.nickname || first.fullname || "").trim() || first.userid || "";
    const secondName = (second.nickname || second.fullname || "").trim() || second.userid || "";
    const byName = firstName.localeCompare(secondName, sortLocale.value);
    if (byName !== 0) return byName;
    return String(first.userid || "").localeCompare(String(second.userid || ""), sortLocale.value);
  });

const loadContacts = async () => {
  try {
    loadingContacts.value = true;
    const res = await chatApi.getContacts();
    contacts.value = sortUsers((res.data?.contacts || []).map((contact) => ({ ...contact, isContact: true })));
    chatSearchResults.value = {
      ...chatSearchResults.value,
      contacts: (chatSearchResults.value.contacts || []).map(withContactState),
    };
    contactLookupUsers.value = contactLookupUsers.value.map(withContactState);
  } catch (error) {
    showApiError(error);
  } finally {
    loadingContacts.value = false;
  }
};

const searchChatRealtime = async (keyword, scope) => {
  const requestId = ++searchRequestId;
  try {
    const [res, userRes] = await Promise.all([
      chatApi.searchChat(keyword, scope),
      chatApi.searchUsers(keyword),
    ]);
    if (requestId !== searchRequestId || keyword !== searchKeyword.value.trim() || scope !== searchScope.value) return;
    const results = res.data?.results || {};
    const exactUser = (userRes.data?.users || []).find((user) =>
      useridsMatch(user.userid, keyword),
    );
    chatSearchResults.value = {
      contacts: (results.contacts || []).map(withContactState),
      messages: results.messages || [],
      files: results.files || [],
    };
    chatSearchUserResult.value = exactUser ? withContactState(exactUser) : null;
  } catch (error) {
    if (requestId === searchRequestId) showApiError(error);
  } finally {
    if (requestId === searchRequestId) searchingChat.value = false;
  }
};

const searchContactLookup = async (keyword) => {
  const requestId = ++contactLookupRequestId;
  try {
    const res = await chatApi.searchUsers(keyword);
    if (requestId !== contactLookupRequestId || keyword !== contactUserid.value.trim()) return;
    const exactUser = (res.data?.users || []).find((user) =>
      useridsMatch(user.userid, keyword),
    );
    contactLookupUsers.value = exactUser ? [withContactState(exactUser)] : [];
  } catch (error) {
    if (requestId === contactLookupRequestId) showApiError(error);
  } finally {
    if (requestId === contactLookupRequestId) contactLookupLoading.value = false;
  }
};

const openContactDialog = () => {
  contactDialogVisible.value = true;
  contactUserid.value = "";
  contactLookupUsers.value = [];
};

const upsertContact = (contact) => {
  if (!contact?.userid) return;
  const nextContact = { ...contact, isContact: true };
  const withoutCurrent = contacts.value.filter((item) => !useridsMatch(item.userid, nextContact.userid));
  contacts.value = sortUsers([...withoutCurrent, nextContact]);
  chatSearchResults.value = {
    ...chatSearchResults.value,
    contacts: (chatSearchResults.value.contacts || []).map((user) =>
      useridsMatch(user.userid, nextContact.userid) ? { ...user, isContact: true } : user,
    ),
  };
  contactLookupUsers.value = contactLookupUsers.value.map((user) =>
    useridsMatch(user.userid, nextContact.userid) ? { ...user, isContact: true } : user,
  );
};

const findExactUserByUserid = async (userid) => {
  const query = String(userid || "").trim();
  if (!query) return null;
  const res = await chatApi.searchUsers(query);
  return (res.data?.users || []).find((user) => useridsMatch(user.userid, query)) || null;
};

const addContactByUserid = async (userid, verifiedUser = null) => {
  const contactUseridValue = String(userid || "").trim();
  if (!contactUseridValue) {
    ElMessage.warning(homeT("messages.enterUserid"));
    return null;
  }
  if (useridsMatch(contactUseridValue, currentUserid)) {
    ElMessage.warning(homeT("messages.cannotAddSelf"));
    return null;
  }

  const user = verifiedUser && useridsMatch(verifiedUser.userid, contactUseridValue)
    ? verifiedUser
    : await findExactUserByUserid(contactUseridValue);
  if (!user) {
    ElMessage.warning(homeT("search.noResults"));
    return null;
  }

  const res = await chatApi.addContact(user.userid);
  const contact = res.data?.contact;
  upsertContact(contact);
  ElMessage.success(homeT("messages.contactAdded"));
  return contact;
};

const addContactFromUser = async (user) => {
  try {
    await addContactByUserid(user.userid, user);
  } catch (error) {
    showApiError(error);
  }
};

const addContactFromSearchUser = async (user) => {
  await addContactFromUser(user);
  if (user?.userid && isContactUser(user.userid)) {
    chatSearchUserResult.value = withContactState(user);
  }
};

const addActiveConversationContact = async () => {
  const peer = directConversationPeer(activeConversation.value);
  if (!peer?.userid) return;
  try {
    await addContactByUserid(peer.userid, peer);
  } catch (error) {
    showApiError(error);
  }
};

const submitAddContact = async () => {
  try {
    const contact = await addContactByUserid(contactUserid.value);
    if (!contact) return;
    contactDialogVisible.value = false;
    contactUserid.value = "";
    panelMode.value = "contacts";
    contactSection.value = "friends";
  } catch (error) {
    showApiError(error);
  }
};

const loadProfile = async () => {
  try {
    const res = await chatApi.getProfile();
    applyProfile(res.data?.user);
  } catch (error) {
    showApiError(error);
  }
};

const applyProfile = (user) => {
  if (!user) return;
  currentUser.value = {
    userid: user.userid,
    fullname: user.fullname || user.userid,
    avatar: user.avatar || "",
  };
  profileForm.value = { ...currentUser.value };
  localStorage.setItem("userid", currentUser.value.userid);
  localStorage.setItem("fullname", currentUser.value.fullname);
  localStorage.setItem("avatar", currentUser.value.avatar);
};

const openProfileDialog = async () => {
  profileDialogVisible.value = true;
  profileForm.value = { ...currentUser.value };
  passwordForm.value = { currentPassword: "", newPassword: "", confirmPassword: "" };
  passwordDialogVisible.value = false;
  await loadProfile();
};

const openMemberProfile = (member) => {
  if (!member?.userid) return;
  memberProfileTarget.value = member;
  memberProfileDialogVisible.value = true;
};

const openMessageSenderProfile = (message) => {
  if (!message?.senderUserid) return;
  const member = (activeConversation.value?.members || []).find((item) =>
    useridsMatch(item.userid, message.senderUserid),
  );
  if (member) openMemberProfile(member);
};

const addContactFromMemberProfile = async () => {
  const member = memberProfileTarget.value;
  if (!member?.userid) return;
  try {
    const contact = await addContactByUserid(member.userid, member);
    if (contact) {
      memberProfileTarget.value = {
        ...member,
        ...contact,
        nickname: activeConversation.value?.type === "group" ? member.nickname : contact.nickname,
        isContact: true,
      };
    }
  } catch (error) {
    showApiError(error);
  }
};

const startPrivateChatFromMemberProfile = async () => {
  const userid = memberProfileTarget.value?.userid;
  if (!userid) return;
  memberProfileDialogVisible.value = false;
  await startDirectChat(userid);
};

const openPasswordDialog = () => {
  passwordForm.value = { currentPassword: "", newPassword: "", confirmPassword: "" };
  passwordDialogVisible.value = true;
};

const saveProfile = async () => {
  if (!profileForm.value.fullname.trim()) {
    ElMessage.warning(homeT("messages.enterDisplayName"));
    return;
  }

  try {
    const res = await chatApi.updateProfile(profileForm.value.fullname.trim());
    applyProfile(res.data?.user);
    await loadConversations(false);
    ElMessage.success(homeT("messages.profileUpdated"));
  } catch (error) {
    showApiError(error);
  }
};

const savePassword = async () => {
  if (!passwordForm.value.currentPassword || !passwordForm.value.newPassword) {
    ElMessage.warning(homeT("messages.enterPasswords"));
    return;
  }
  if (passwordForm.value.newPassword.length < 6) {
    ElMessage.warning(homeT("messages.passwordMinLength"));
    return;
  }
  if (passwordForm.value.newPassword !== passwordForm.value.confirmPassword) {
    ElMessage.warning(homeT("messages.passwordMismatch"));
    return;
  }

  try {
    await chatApi.changePassword(passwordForm.value.currentPassword, passwordForm.value.newPassword);
    passwordForm.value = { currentPassword: "", newPassword: "", confirmPassword: "" };
    passwordDialogVisible.value = false;
    ElMessage.success(homeT("messages.passwordChanged"));
  } catch (error) {
    showApiError(error);
  }
};

const handleAvatarSelected = async (event) => {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file) return;

  try {
    const res = await chatApi.uploadAvatar(file);
    applyProfile(res.data?.user);
    await loadConversations(false);
    ElMessage.success(homeT("messages.avatarUpdated"));
  } catch (error) {
    showApiError(error);
  }
};

const handleGroupImageSelected = async (event, field) => {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file || !activeConversationId.value || !activeConversation.value) return;
  if (field === "avatar" && activeConversation.value.type !== "group") return;

  try {
    const uploadRes = await chatApi.uploadFiles([{ file, relativePath: file.name }]);
    const attachment = uploadRes.data?.attachments?.[0];
    if (!attachment?.fileUrl) {
      ElMessage.error(homeT("messages.imageUploadFailed"));
      return;
    }

    const payload = {
      avatar: activeConversation.value.avatar || "",
      background: activeConversation.value.background || "",
      [field]: attachment.fileUrl,
    };
    const res = await chatApi.updateConversationSettings(activeConversationId.value, payload);
    await loadConversations(false);
    if (res.data?.conversation) {
      await selectConversation(res.data.conversation);
    }
    ElMessage.success(field === "avatar" ? homeT("messages.groupAvatarUpdated") : homeT("messages.groupBackgroundUpdated"));
  } catch (error) {
    showApiError(error);
  }
};

const loadConversations = async (selectFirst = false, options = {}) => {
  const silent = Boolean(options.silent);
  try {
    if (!silent) loadingConversations.value = true;
    const res = await chatApi.getConversations();
    const nextConversations = sortConversationsForDisplay(res.data?.conversations || []);
    const isInitialLoad = Object.keys(lastMessageIds.value).length === 0;
    handleConversationNotifications(nextConversations, isInitialLoad);
    conversations.value = nextConversations;

    const activeStillExists = conversations.value.some(
      (conversation) => conversation.id === activeConversationId.value,
    );
    if (!activeStillExists) {
      activeConversationId.value = null;
      messages.value = [];
      messagesHasMore.value = false;
    }
    if (selectFirst && !activeConversationId.value && conversations.value.length) {
      await selectConversation(conversations.value[0]);
    } else if (activeConversationId.value) {
      markConversationRead(activeConversationId.value);
    }
  } catch (error) {
    showApiError(error);
  } finally {
    if (!silent) loadingConversations.value = false;
  }
};

const selectConversation = async (conversation) => {
  activeConversationId.value = conversation.id;
  infoPanelOpen.value = false;
  membersExpanded.value = false;
  cancelReply();
  await loadMessages(conversation.id, true);
  markConversationRead(conversation.id);
};

const openGroupFromDirectory = async (conversation) => {
  panelMode.value = "chats";
  searchKeyword.value = "";
  contactSearchKeyword.value = "";
  await selectConversation(conversation);
};

const messageSortValue = (message = {}) => {
  const createdAt = dayjs(message.createdAt).valueOf() || 0;
  if (message.type !== "poll" || !message.poll?.updatedAt) return createdAt;
  const pollUpdatedAt = dayjs(message.poll.updatedAt).valueOf() || 0;
  return Math.max(createdAt, pollUpdatedAt);
};

const messageSortRank = (message = {}) => {
  if (message.type === "poll") return 1;
  if (message.type === "system") return 2;
  return 0;
};

const sortMessagesForDisplay = (messageList = []) =>
  messageList.slice().sort((first, second) => {
    const timeDiff = messageSortValue(first) - messageSortValue(second);
    if (timeDiff !== 0) return timeDiff;
    const rankDiff = messageSortRank(first) - messageSortRank(second);
    if (rankDiff !== 0) return rankDiff;
    const sequenceDiff = messageSequence(first) - messageSequence(second);
    if (sequenceDiff !== 0) return sequenceDiff;
    const firstId = Number(first.id);
    const secondId = Number(second.id);
    if (Number.isFinite(firstId) && Number.isFinite(secondId)) return firstId - secondId;
    return String(first.id || "").localeCompare(String(second.id || ""));
  });

const mergeMessageLists = (currentMessages = [], nextMessages = []) => {
  const merged = [];
  [...currentMessages, ...nextMessages].forEach((message) => {
    const clientKey = messageDedupeKey(message);
    const index = merged.findIndex((item) => (
      (message.id && item.id === message.id)
      || (clientKey && messageDedupeKey(item) === clientKey)
    ));
    if (index < 0) {
      merged.push(message);
      return;
    }
    const next = { ...merged[index], ...message };
    if (isPersistedMessage(message)) delete next._sendState;
    merged.splice(index, 1, next);
  });
  return sortMessagesForDisplay(merged);
};

const pendingMessagesForConversation = (conversationId) =>
  Object.values(pendingMessages.value)
    .filter((entry) => entry.conversationId === conversationId)
    .map((entry) => entry.optimisticMessage)
    .filter(Boolean);

const updateMessageCursor = (message = {}) => {
  const conversationId = message.conversationId;
  if (!conversationId || !isPersistedMessage(message)) return;
  const key = String(conversationId);
  const previous = messageCursors.value[key] || {};
  const sequence = messageSequence(message);
  const next = {
    afterMessageId: Math.max(Number(previous.afterMessageId || 0), Number(message.id || 0)),
    afterSequence: Math.max(Number(previous.afterSequence || 0), sequence),
  };
  messageCursors.value = { ...messageCursors.value, [key]: next };
  persistMessageCursors();
};

const acknowledgeDelivered = async (message = {}) => {
  if (!message.id || !message.conversationId || isOwnMessage(message)) return;
  const previousHighWater = Number(deliveredHighWaterByConversation.get(message.conversationId) || 0);
  if (Number(message.id) <= previousHighWater) return;
  const key = `${message.conversationId}:${message.id}`;
  if (deliveredAckMessageIds.has(key)) return;
  deliveredAckMessageIds.add(key);
  deliveredHighWaterByConversation.set(message.conversationId, Number(message.id));
  try {
    await chatApi.markMessageDelivered(message.conversationId, message.id);
  } catch {
    deliveredAckMessageIds.delete(key);
    if (Number(deliveredHighWaterByConversation.get(message.conversationId) || 0) === Number(message.id)) {
      deliveredHighWaterByConversation.set(message.conversationId, previousHighWater);
    }
  }
};

const processReceivedMessages = (messageList = []) => {
  let latestInboundMessage = null;
  messageList.forEach((message) => {
    const clientMessageId = messageClientId(message);
    if (
      clientMessageId
      && useridsMatch(message.senderUserid, currentUserid)
      && pendingMessages.value[clientMessageId]
    ) {
      const nextPending = { ...pendingMessages.value };
      delete nextPending[clientMessageId];
      pendingMessages.value = nextPending;
      persistPendingMessages();
    }
    updateMessageCursor(message);
    if (!isOwnMessage(message) && (
      !latestInboundMessage || Number(message.id) > Number(latestInboundMessage.id)
    )) latestInboundMessage = message;
  });
  if (latestInboundMessage) void acknowledgeDelivered(latestInboundMessage);
};

const loadMessages = async (conversationId, shouldScroll = true, options = {}) => {
  const replaceMessages = options.replace ?? shouldScroll;
  const requestId = replaceMessages ? ++messageRequestId : messageRequestId;
  try {
    if (shouldScroll) loadingMessages.value = true;
    const res = await chatApi.getMessages(conversationId, { limit: messagePageSize });
    if (requestId !== messageRequestId || conversationId !== activeConversationId.value) return;

    const nextMessages = res.data?.messages || [];
    processReceivedMessages(nextMessages);
    const withPending = mergeMessageLists(nextMessages, pendingMessagesForConversation(conversationId));
    const responseHasMore = Boolean(res.data?.hasMore);
    if (replaceMessages || messages.value.length === 0) {
      messages.value = sortMessagesForDisplay(withPending);
      messagesHasMore.value = responseHasMore;
    } else {
      messages.value = mergeMessageLists(messages.value, withPending);
      if (messages.value.length <= nextMessages.length) {
        messagesHasMore.value = responseHasMore;
      }
    }

    if (conversationId === activeConversationId.value) {
      markConversationRead(conversationId);
    }
    if (shouldScroll) await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    if (requestId === messageRequestId && shouldScroll) loadingMessages.value = false;
  }
};

const catchUpAfterReconnect = async (cursorSnapshots = null) => {
  const snapshots = cursorSnapshots
    || snapshotCatchUpCursors(conversations.value, messageCursors.value);
  for (const { conversationId, cursor } of snapshots) {
    await catchUpConversation(conversationId, cursor);
  }
};

const catchUpConversation = async (conversationId, cursorSnapshot = {}) => {
  const stored = { ...cursorSnapshot };
  let afterSequence = Number(stored.afterSequence || 0);
  let afterMessageId = Number(stored.afterMessageId || 0);
  let appendedToActive = false;
  let inboundMessagesBelow = 0;
  const shouldStickToBottom = conversationId === activeConversationId.value && isMessageListNearBottom();
  try {
    while (true) {
      const params = { limit: 200 };
      if (afterSequence) params.afterSequence = afterSequence;
      else params.afterMessageId = afterMessageId;
      const res = await chatApi.getMessageCatchUp(conversationId, params);
      const eventMessages = (res.data?.events || [])
        .map((event) => normalizeRealtimeEvent(event).message)
        .filter(Boolean);
      const caughtUpMessages = res.data?.messages || eventMessages;
      if (caughtUpMessages.length) {
        processReceivedMessages(caughtUpMessages);
        if (conversationId === activeConversationId.value) {
          messages.value = mergeMessageLists(messages.value, caughtUpMessages);
          appendedToActive = true;
          if (!shouldStickToBottom) {
            inboundMessagesBelow += caughtUpMessages.filter((message) => !isOwnMessage(message)).length;
          }
        }
      }

      const nextSequence = Number(
        res.data?.nextSequence
        || res.data?.nextCursor?.afterSequence
        || res.data?.nextCursor?.serverSequence
        || 0,
      )
        || Math.max(afterSequence, ...caughtUpMessages.map(messageSequence));
      const nextMessageId = Number(
        res.data?.nextMessageId
        || res.data?.nextCursor?.afterMessageId
        || res.data?.nextCursor?.messageId
        || 0,
      )
        || Math.max(afterMessageId, ...caughtUpMessages.map((message) => Number(message.id || 0)));
      const progressed = nextSequence > afterSequence || nextMessageId > afterMessageId;
      afterSequence = Math.max(afterSequence, nextSequence);
      afterMessageId = Math.max(afterMessageId, nextMessageId);
      if (!res.data?.hasMore || !progressed) break;
    }
    const mergedCursor = mergeCatchUpCursor(
      messageCursors.value[String(conversationId)] || {},
      { afterSequence, afterMessageId },
    );
    messageCursors.value = {
      ...messageCursors.value,
      [String(conversationId)]: mergedCursor,
    };
    persistMessageCursors();
    if (appendedToActive) {
      markConversationRead(conversationId);
      if (shouldStickToBottom) await scrollToBottom();
      else registerNewMessagesBelow(inboundMessagesBelow);
    }
  } catch {
    // Keep the last processed cursor. A broad snapshot here could jump over the
    // failed catch-up gap, so the next reconnect resumes from the safe boundary.
  }
};

const loadOlderMessages = async () => {
  if (!activeConversationId.value || !messagesHasMore.value || loadingOlderMessages.value || loadingMessages.value) return;
  if (!messages.value.length) return;

  const conversationId = activeConversationId.value;
  const beforeId = messages.value[0].id;
  const listEl = messageListRef.value;
  const previousScrollHeight = listEl?.scrollHeight || 0;

  try {
    loadingOlderMessages.value = true;
    const res = await chatApi.getMessages(conversationId, {
      limit: messagePageSize,
      beforeId,
    });
    if (conversationId !== activeConversationId.value) return;

    const olderMessages = res.data?.messages || [];
    processReceivedMessages(olderMessages);
    if (olderMessages.length) {
      messages.value = mergeMessageLists(olderMessages, messages.value);
      await nextTick();
      if (listEl) {
        listEl.scrollTop += listEl.scrollHeight - previousScrollHeight;
      }
    }
    messagesHasMore.value = Boolean(res.data?.hasMore);
  } catch (error) {
    showApiError(error);
  } finally {
    loadingOlderMessages.value = false;
  }
};

const openInfoPanel = async () => {
  infoPanelOpen.value = true;
  if (loadingInfoPanelHistory.value || !messagesHasMore.value) return;

  const conversationId = activeConversationId.value;
  loadingInfoPanelHistory.value = true;
  try {
    while (conversationId === activeConversationId.value && messagesHasMore.value) {
      if (loadingOlderMessages.value) {
        await new Promise((resolve) => window.setTimeout(resolve, 60));
        continue;
      }
      const previousCount = messages.value.length;
      await loadOlderMessages();
      if (messages.value.length === previousCount && messagesHasMore.value) break;
    }
  } finally {
    loadingInfoPanelHistory.value = false;
  }
};

const handleMessageListScroll = () => {
  const listEl = messageListRef.value;
  if (!listEl) return;
  const nearBottom = isMessageListNearBottom();
  showLatestButton.value = !nearBottom;
  if (nearBottom) newMessagesBelowCount.value = 0;
  if (listEl.scrollTop <= 80) void loadOlderMessages();
};

const startDirectChat = async (userid) => {
  const targetUserid = String(userid || "").trim();
  if (!targetUserid) {
    ElMessage.warning(homeT("messages.enterChatUserid"));
    return;
  }
  if (useridsMatch(targetUserid, currentUserid)) {
    ElMessage.warning(homeT("messages.cannotChatSelf"));
    return;
  }

  try {
    const res = await chatApi.createDirectConversation(targetUserid);
    const conversation = res.data?.conversation;
    panelMode.value = "chats";
    searchKeyword.value = "";
    contactDialogVisible.value = false;
    await loadConversations(false);
    if (conversation) await selectConversation(conversation);
  } catch (error) {
    showApiError(error);
  }
};

const openGroupDialog = async () => {
  groupDialogVisible.value = true;
  groupName.value = "";
  groupMemberInput.value = "";
  groupMemberUserids.value = [];
  await loadContacts();
};

const addGroupMemberChip = () => {
  const userid = groupMemberInput.value.trim();
  if (!userid) return;
  if (!useridsInclude(groupMemberUserids.value, userid) && !useridsMatch(userid, currentUserid)) {
    groupMemberUserids.value.push(userid);
  }
  groupMemberInput.value = "";
};

const removeGroupMemberChip = (userid) => {
  groupMemberUserids.value = groupMemberUserids.value.filter((item) => !useridsMatch(item, userid));
};

const toggleGroupMember = (userid) => {
  if (!userid || useridsMatch(userid, currentUserid)) return;
  if (useridsInclude(groupMemberUserids.value, userid)) {
    removeGroupMemberChip(userid);
    return;
  }
  groupMemberUserids.value.push(userid);
};

const createGroup = async () => {
  addGroupMemberChip();
  if (!groupName.value) {
    ElMessage.warning(homeT("messages.enterGroupName"));
    return;
  }

  try {
    const res = await chatApi.createGroupConversation(groupName.value, groupMemberUserids.value);
    groupDialogVisible.value = false;
    await loadConversations(false);
    if (res.data?.conversation) await selectConversation(res.data.conversation);
  } catch (error) {
    showApiError(error);
  }
};

const openAddMemberDialog = async () => {
  if (!activeConversationId.value) return;
  if (activeConversation.value?.type !== "group") {
    ElMessage.warning(homeT("messages.groupOnlyAddMembers"));
    return;
  }
  addMemberDialogVisible.value = true;
  addMemberInput.value = "";
  addMemberUserids.value = [];
  await loadContacts();
};

const addMemberChip = () => {
  const userid = addMemberInput.value.trim();
  if (!userid) return;
  const currentMemberUserids = activeConversation.value?.members?.map((member) => member.userid) || [];
  if (!useridsInclude(addMemberUserids.value, userid) && !useridsInclude(currentMemberUserids, userid)) {
    addMemberUserids.value.push(userid);
  }
  addMemberInput.value = "";
};

const removeAddMemberChip = (userid) => {
  addMemberUserids.value = addMemberUserids.value.filter((item) => !useridsMatch(item, userid));
};

const toggleAddMember = (userid) => {
  if (!userid || useridsMatch(userid, currentUserid)) return;
  const currentMemberUserids = activeConversation.value?.members?.map((member) => member.userid) || [];
  if (useridsInclude(currentMemberUserids, userid)) return;
  if (useridsInclude(addMemberUserids.value, userid)) {
    removeAddMemberChip(userid);
    return;
  }
  addMemberUserids.value.push(userid);
};

const submitAddMembers = async () => {
  addMemberChip();
  if (!activeConversationId.value || addMemberUserids.value.length === 0) {
    ElMessage.warning(homeT("messages.enterMemberUserid"));
    return;
  }

  try {
    await chatApi.addConversationMembers(activeConversationId.value, addMemberUserids.value);
    addMemberDialogVisible.value = false;
    await loadConversations(false);
  } catch (error) {
    showApiError(error);
  }
};

const removeMemberFromGroup = async (member) => {
  if (!activeConversationId.value || !member?.userid) return;
  if (!isCurrentUserGroupOwner.value) {
    ElMessage.warning(homeT("messages.ownerOnlyRemoveMembers"));
    return;
  }
  if (useridsMatch(member.userid, currentUserid)) return;

  const memberName = member.fullname || member.userid;
  try {
    await ElMessageBox.confirm(
      homeT("messages.removeMemberConfirm", { name: memberName }),
      homeT("messages.removeMemberTitle"),
      {
        confirmButtonText: homeT("actions.remove"),
        cancelButtonText: homeT("actions.cancel"),
        type: "warning",
      },
    );
  } catch {
    return;
  }

  try {
    await chatApi.removeConversationMember(activeConversationId.value, member.userid);
    await loadConversations(false);
    ElMessage.success(homeT("messages.memberRemoved"));
  } catch (error) {
    showApiError(error);
  }
};

const openNicknameDialog = (member, scope = "") => {
  if (!member?.userid) return;
  const resolvedScope = scope || (activeConversation.value?.type === "group" ? "group" : "contact");
  if (resolvedScope === "group" && !activeConversationId.value) return;
  if (resolvedScope === "contact" && !isContactUser(member.userid)) return;
  nicknameScope.value = resolvedScope;
  nicknameTarget.value = member;
  nicknameValue.value = member.nickname || "";
  nicknameDialogVisible.value = true;
};

const openNicknameFromMemberProfile = async () => {
  const member = memberProfileTarget.value;
  if (!member?.userid) return;
  const scope = activeConversation.value?.type === "group" ? "group" : "contact";
  memberProfileDialogVisible.value = false;
  await nextTick();
  openNicknameDialog(member, scope);
};

const submitNickname = async () => {
  if (!nicknameTarget.value?.userid) return;

  try {
    const targetUserid = nicknameTarget.value.userid;
    if (nicknameScope.value === "contact") {
      const res = await chatApi.updateContactNickname(targetUserid, nicknameValue.value);
      upsertContact(res.data?.contact);
    } else {
      if (!activeConversationId.value) return;
      await chatApi.updateConversationMemberNickname(
        activeConversationId.value,
        targetUserid,
        nicknameValue.value,
      );
    }
    nicknameDialogVisible.value = false;
    const conversationId = activeConversationId.value;
    await loadConversations(false);
    if (conversationId) {
      await loadMessages(conversationId, false);
    }
    memberProfileTarget.value = memberProfileTarget.value?.userid === targetUserid
      ? { ...memberProfileTarget.value, nickname: nicknameValue.value }
      : memberProfileTarget.value;
    ElMessage.success(nicknameValue.value ? homeT("messages.nicknameSaved") : homeT("messages.nicknameRemoved"));
  } catch (error) {
    showApiError(error);
  }
};

const sendTypingSignal = (conversationId, isTyping) => {
  if (!conversationId) return;
  const type = isTyping ? "typing.start" : "typing.stop";
  const sentOverSocket = sendRealtimeEvent({
    type,
    conversationId,
    version: 1,
    payload: { conversationId, isTyping },
  });
  if (!sentOverSocket) {
    void chatApi.setTyping(conversationId, isTyping).catch(() => {});
  }
};

const startLocalTyping = () => {
  const conversationId = activeConversationId.value;
  if (!conversationId || !composerText.value.trim()) {
    stopLocalTyping();
    return;
  }
  const now = Date.now();
  if (typingConversationId !== conversationId || now - typingLastSentAt >= 1800) {
    if (typingConversationId && typingConversationId !== conversationId) {
      sendTypingSignal(typingConversationId, false);
    }
    sendTypingSignal(conversationId, true);
    typingLastSentAt = now;
    typingConversationId = conversationId;
  }
  if (typingStopTimer) window.clearTimeout(typingStopTimer);
  typingStopTimer = window.setTimeout(() => stopLocalTyping(), 2500);
};

const stopLocalTyping = (force = false, conversationId = typingConversationId) => {
  if (typingStopTimer) {
    window.clearTimeout(typingStopTimer);
    typingStopTimer = null;
  }
  if (conversationId && (force || typingConversationId === conversationId)) {
    sendTypingSignal(conversationId, false);
  }
  if (!conversationId || typingConversationId === conversationId) {
    typingConversationId = null;
    typingLastSentAt = 0;
  }
};

const handleComposerInput = () => {
  updateMentionState();
  startLocalTyping();
};

const applyTypingEvent = (event = {}) => {
  const conversationId = event.conversationId;
  const userid = event.userid || event.payload?.senderUserid || event.payload?.sender_userid;
  if (!conversationId || !userid || useridsMatch(userid, currentUserid)) return;
  const conversationKey = String(conversationId);
  const userKey = String(userid);
  const timerKey = `${conversationKey}:${userKey}`;
  const currentConversationTyping = { ...(typingUsers.value[conversationKey] || {}) };
  if (event.type === "typing.stop") {
    delete currentConversationTyping[userKey];
    const timer = typingExpiryTimers.get(timerKey);
    if (timer) window.clearTimeout(timer);
    typingExpiryTimers.delete(timerKey);
  } else {
    const member = conversations.value
      .find((conversation) => conversation.id === conversationId)
      ?.members?.find((item) => useridsMatch(item.userid, userid));
    currentConversationTyping[userKey] = {
      userid,
      name: event.payload?.fullname || event.payload?.senderName || event.payload?.sender_name || displayName(member) || userid,
      expiresAt: Date.now() + 6000,
    };
    const previousTimer = typingExpiryTimers.get(timerKey);
    if (previousTimer) window.clearTimeout(previousTimer);
    typingExpiryTimers.set(timerKey, window.setTimeout(() => {
      const nextConversationTyping = { ...(typingUsers.value[conversationKey] || {}) };
      delete nextConversationTyping[userKey];
      typingUsers.value = { ...typingUsers.value, [conversationKey]: nextConversationTyping };
      typingExpiryTimers.delete(timerKey);
    }, 6100));
  }
  typingUsers.value = { ...typingUsers.value, [conversationKey]: currentConversationTyping };
};

const updateMentionState = () => {
  if (!activeConversation.value) {
    closeMentionMenu();
    return;
  }

  const input = composerInputRef.value;
  const cursor = input?.selectionStart ?? composerText.value.length;
  const textBeforeCursor = composerText.value.slice(0, cursor);
  const atIndex = textBeforeCursor.lastIndexOf("@");

  if (atIndex < 0) {
    closeMentionMenu();
    return;
  }

  const charBeforeAt = atIndex === 0 ? " " : textBeforeCursor[atIndex - 1];
  const query = textBeforeCursor.slice(atIndex + 1);
  if (!/\s/.test(charBeforeAt) || query.includes("\n") || query.includes("@")) {
    closeMentionMenu();
    return;
  }

  const queryChanged = mentionQuery.value !== query;
  mentionStartIndex.value = atIndex;
  mentionQuery.value = query;
  mentionActive.value = true;
  mentionSelectedIndex.value = queryChanged
    ? 0
    : Math.min(mentionSelectedIndex.value, Math.max(mentionSuggestions.value.length - 1, 0));
};

const closeMentionMenu = () => {
  mentionActive.value = false;
  mentionQuery.value = "";
  mentionStartIndex.value = -1;
  mentionSelectedIndex.value = 0;
};

const moveMentionSelection = (direction) => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return;
  const total = mentionSuggestions.value.length;
  mentionSelectedIndex.value = (mentionSelectedIndex.value + direction + total) % total;
};

const handleMentionArrow = (event, direction) => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return;
  event.preventDefault();
  moveMentionSelection(direction);
};

const handleMentionTab = (event) => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return;
  event.preventDefault();
  applySelectedMention();
};

const applySelectedMention = () => {
  if (!mentionActive.value || !mentionSuggestions.value.length) return false;
  insertMention(mentionSuggestions.value[mentionSelectedIndex.value] || mentionSuggestions.value[0]);
  return true;
};

const handleComposerEnter = () => {
  if (applySelectedMention()) return;
  sendCurrentMessage();
};

const insertMention = async (member) => {
  const input = composerInputRef.value;
  const cursor = input?.selectionStart ?? composerText.value.length;
  const start = mentionStartIndex.value >= 0 ? mentionStartIndex.value : cursor;
  const mentionText = `@${mentionOptionName(member) || member.userid} `;
  composerText.value = `${composerText.value.slice(0, start)}${mentionText}${composerText.value.slice(cursor)}`;
  closeMentionMenu();

  await nextTick();
  const nextCursor = start + mentionText.length;
  composerInputRef.value?.focus();
  composerInputRef.value?.setSelectionRange(nextCursor, nextCursor);
};

const handleFilesSelected = async (event, type) => {
  const files = Array.from(event.target.files || []);
  event.target.value = "";
  await prepareAndUploadFiles(files.map((file) => ({ file, relativePath: file.webkitRelativePath || file.name })), type);
};

const prepareAndUploadFiles = async (fileItems, type) => {
  if (!fileItems.length) return;

  try {
    uploading.value = true;
    const res = await chatApi.uploadFiles(fileItems);
    pendingAttachments.value = [
      ...pendingAttachments.value,
      ...(res.data?.attachments || []),
    ];
    pendingAttachmentType.value = type;

    if (type === "folder" && !composerText.value) {
      composerText.value = folderNameFromPath(fileItems[0].relativePath) || homeT("fileKinds.folder");
    }
    ElMessage.success(homeT("messages.filesUploaded", { count: fileItems.length }));
  } catch (error) {
    showApiError(error);
  } finally {
    uploading.value = false;
  }
};

const toggleVoiceRecording = () => {
  if (isRecording.value) {
    stopVoiceRecording();
    return;
  }
  startVoiceRecording();
};

const startVoiceRecording = async () => {
  if (!activeConversationId.value) {
    ElMessage.warning(homeT("messages.selectConversationBeforeVoice"));
    return;
  }
  if (preparingRecording.value || isRecording.value || sending.value || uploading.value) return;
  if (pendingAttachments.value.length) {
    ElMessage.warning(homeT("messages.clearPendingBeforeVoice"));
    return;
  }
  if (!window.navigator?.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
    ElMessage.error(homeT("messages.recordingUnsupported"));
    return;
  }

  try {
    preparingRecording.value = true;
    const stream = await window.navigator.mediaDevices.getUserMedia({ audio: true });
    recordingStream = stream;
    if (componentUnmounted) {
      releaseRecordingStream();
      return;
    }
    const mimeType = supportedAudioMimeType();
    const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);

    mediaRecorder = recorder;
    recordingChunks = [];
    discardRecording = false;

    recorder.ondataavailable = (event) => {
      if (event.data?.size) {
        recordingChunks.push(event.data);
      }
    };
    recorder.onerror = () => {
      ElMessage.error(homeT("messages.recordingFailed"));
      cancelVoiceRecording();
    };
    recorder.onstop = () => finalizeVoiceRecording(recorder.mimeType || mimeType);

    recorder.start();
    isRecording.value = true;
    recordingDuration.value = 0;
    recordingStartedAt = Date.now();
    recordingTimer = window.setInterval(updateRecordingDuration, 250);
  } catch {
    releaseRecordingStream();
    ElMessage.error(homeT("messages.microphoneAccessFailed"));
  } finally {
    preparingRecording.value = false;
  }
};

const stopVoiceRecording = () => {
  if (!mediaRecorder || mediaRecorder.state === "inactive") return;
  mediaRecorder.stop();
};

const cancelVoiceRecording = () => {
  discardRecording = true;
  if (mediaRecorder && mediaRecorder.state !== "inactive") {
    mediaRecorder.stop();
    return;
  }
  resetRecordingState();
};

const finalizeVoiceRecording = async (mimeType) => {
  const chunks = [...recordingChunks];
  const shouldDiscard = discardRecording;
  resetRecordingState();

  if (shouldDiscard) return;
  if (!chunks.length) {
    ElMessage.warning(homeT("messages.emptyVoice"));
    return;
  }

  const blobType = mimeType || chunks[0]?.type || "audio/webm";
  const blob = new Blob(chunks, { type: blobType });
  if (!blob.size) {
    ElMessage.warning(homeT("messages.emptyVoice"));
    return;
  }

  const file = new File([blob], `voice-${dayjs().format("YYYYMMDD-HHmmss")}.${audioExtension(blob.type)}`, {
    type: blob.type || "audio/webm",
  });
  await sendVoiceMessage(file);
};

const sendVoiceMessage = async (file) => {
  if (!activeConversationId.value) return;

  try {
    uploading.value = true;
    const uploadRes = await chatApi.uploadFiles([{ file, relativePath: file.name }]);
    const attachments = uploadRes.data?.attachments || [];
    if (!attachments.length) {
      ElMessage.error(homeT("messages.voiceUploadFailed"));
      return;
    }

    sending.value = true;
    await queueMessageSend(activeConversationId.value, {
      type: "voice",
      content: "",
      attachments,
    });
    await loadConversations(false);
    await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    uploading.value = false;
    sending.value = false;
  }
};

const supportedAudioMimeType = () => {
  if (typeof MediaRecorder === "undefined" || typeof MediaRecorder.isTypeSupported !== "function") {
    return "";
  }
  return [
    "audio/webm;codecs=opus",
    "audio/webm",
    "audio/ogg;codecs=opus",
    "audio/mp4",
  ].find((type) => MediaRecorder.isTypeSupported(type)) || "";
};

const audioExtension = (mimeType = "") => {
  const normalized = mimeType.toLowerCase();
  if (normalized.includes("mp4")) return "m4a";
  if (normalized.includes("ogg")) return "ogg";
  if (normalized.includes("wav")) return "wav";
  return "webm";
};

const updateRecordingDuration = () => {
  if (!recordingStartedAt) return;
  recordingDuration.value = Math.max(0, Math.floor((Date.now() - recordingStartedAt) / 1000));
};

const resetRecordingState = () => {
  if (recordingTimer) {
    window.clearInterval(recordingTimer);
    recordingTimer = null;
  }
  releaseRecordingStream();
  mediaRecorder = null;
  recordingChunks = [];
  recordingStartedAt = 0;
  discardRecording = false;
  isRecording.value = false;
  recordingDuration.value = 0;
};

const releaseRecordingStream = () => {
  recordingStream?.getTracks().forEach((track) => track.stop());
  recordingStream = null;
};

const onDragEnter = (event) => {
  if (!hasFiles(event)) return;
  dragDepth.value += 1;
  isDragging.value = true;
};

const onDragOver = (event) => {
  if (!hasFiles(event)) return;
  event.dataTransfer.dropEffect = activeConversationId.value ? "copy" : "none";
  isDragging.value = true;
};

const onDragLeave = () => {
  dragDepth.value = Math.max(0, dragDepth.value - 1);
  if (dragDepth.value === 0) {
    isDragging.value = false;
  }
};

const handleDrop = async (event) => {
  dragDepth.value = 0;
  isDragging.value = false;

  if (!activeConversationId.value) {
    ElMessage.warning(homeT("messages.selectConversationBeforeFile"));
    return;
  }

  const fileItems = await filesFromDrop(event.dataTransfer);
  const hasFolder = fileItems.some((item) => item.relativePath.includes("/"));
  await prepareAndUploadFiles(fileItems, hasFolder ? "folder" : "file");
};

const filesFromDrop = async (dataTransfer) => {
  const items = Array.from(dataTransfer?.items || []);
  const entries = items
    .map((item) => (typeof item.webkitGetAsEntry === "function" ? item.webkitGetAsEntry() : null))
    .filter(Boolean);

  if (entries.length) {
    const nested = await Promise.all(entries.map((entry) => readEntry(entry, "")));
    return nested.flat();
  }

  return Array.from(dataTransfer?.files || []).map((file) => ({
    file,
    relativePath: file.webkitRelativePath || file.name,
  }));
};

const readEntry = (entry, parentPath) => {
  if (entry.isFile) {
    return new Promise((resolve, reject) => {
      entry.file(
        (file) => resolve([{ file, relativePath: `${parentPath}${file.name}` }]),
        reject,
      );
    });
  }

  if (!entry.isDirectory) return Promise.resolve([]);

  const directoryPath = `${parentPath}${entry.name}/`;
  const reader = entry.createReader();
  const batches = [];

  return new Promise((resolve, reject) => {
    const readBatch = () => {
      reader.readEntries(async (entries) => {
        if (!entries.length) {
          try {
            const nested = await Promise.all(batches.map((child) => readEntry(child, directoryPath)));
            resolve(nested.flat());
          } catch (error) {
            reject(error);
          }
          return;
        }
        batches.push(...entries);
        readBatch();
      }, reject);
    };

    readBatch();
  });
};

const hasFiles = (event) => Array.from(event.dataTransfer?.types || []).includes("Files");

const removePendingAttachment = (fileUrl) => {
  pendingAttachments.value = pendingAttachments.value.filter(
    (attachment) => attachment.fileUrl !== fileUrl,
  );
};

const startReply = (message) => {
  replyingTo.value = toMessageReference(message);
  nextTick(() => composerInputRef.value?.focus());
};

const cancelReply = () => {
  replyingTo.value = null;
};

const isPinnedMessage = (message = {}) => activePinnedMessages.value.some((item) => item.id === message.id);

const applyPinnedMessageState = (conversationId, state = {}) => {
  const normalizedConversationId = Number(conversationId || state.conversationId || 0);
  if (!normalizedConversationId) return;
  conversations.value = conversations.value.map((conversation) => (
    conversation.id === normalizedConversationId
      ? {
        ...conversation,
        pinnedMessage: state.pinnedMessage || null,
        pinnedMessages: Array.isArray(state.pinnedMessages)
          ? state.pinnedMessages
          : (state.pinnedMessage ? [state.pinnedMessage] : []),
        pinnedCount: Number(state.pinnedCount || state.pinnedMessages?.length || (state.pinnedMessage ? 1 : 0)),
        messagePinnedBy: state.pinnedBy || "",
        messagePinnedByName: state.pinnedByName || "",
        messagePinnedAt: state.pinnedAt || null,
      }
      : conversation
  ));
};

const applyPinnedMessageEvent = (event = {}) => {
  applyPinnedMessageState(event.conversationId, event.payload || {});
};

const applyPinnedMessageResponse = async (conversationId, state = {}) => {
  applyPinnedMessageState(conversationId, state);
  const systemMessage = state.systemMessage;
  if (systemMessage?.id) {
    processReceivedMessages([systemMessage]);
    if (Number(systemMessage.conversationId) === Number(activeConversationId.value)) {
      upsertMessage(systemMessage);
      await nextTick();
      await scrollToBottom();
    }
  }
  await loadConversations(false, { silent: true });
};

const pinMessage = async (message = {}) => {
  if (!activeConversationId.value || !message.id) return;
  try {
    const response = await chatApi.setPinnedMessage(activeConversationId.value, message.id);
    await applyPinnedMessageResponse(activeConversationId.value, response.data?.pinState || {});
  } catch (error) {
    showApiError(error);
  }
};

const unpinMessage = async (message = {}) => {
  if (!activeConversationId.value || !message.id) return;
  try {
    const response = await chatApi.setPinnedMessage(activeConversationId.value, message.id, false);
    await applyPinnedMessageResponse(activeConversationId.value, response.data?.pinState || {});
  } catch (error) {
    showApiError(error);
  }
};

const handleMessageOption = (command, message) => {
  if (command === "pin") {
    pinMessage(message);
    return;
  }
  if (command === "unpin") {
    unpinMessage(message);
    return;
  }
  if (command === "copy") {
    void copyMessage(message);
    return;
  }
  if (command === "editHistory") {
    void openMessageEditHistory(message);
    return;
  }
  if (command === "edit") {
    void editExistingMessage(message);
    return;
  }
  if (command === "recall") {
    void recallExistingMessage(message);
    return;
  }
  if (command === "deleteForMe") {
    void deleteExistingMessageForMe(message);
  }
};

const isMessageRecalled = (message = {}) => Boolean(
  message.isRecalled
  || message.recalledAt
  || message.recalled_at
  || message.deletedAt
  || message.deleted_at,
);

const canEditMessage = (message = {}) => (
  isPersistedMessage(message)
  && isOwnMessage(message)
  && !isMessageRecalled(message)
  && ["text", "link"].includes(message.type)
);

const recallWindowSeconds = Number(import.meta.env.VITE_MESSAGE_RECALL_WINDOW_SECONDS || 120);

const canRecallMessage = (message = {}) => {
  if (!isPersistedMessage(message) || !isOwnMessage(message) || isMessageRecalled(message)) return false;
  if (typeof message.canRecall === "boolean") return message.canRecall;
  const createdAt = dayjs(message.createdAt);
  if (!createdAt.isValid()) return false;
  return dayjs().diff(createdAt, "second") <= recallWindowSeconds;
};

const editExistingMessage = async (message) => {
  if (!canEditMessage(message)) return;
  try {
    const result = await ElMessageBox.prompt(homeT("messages.editMessagePrompt"), homeT("chat.editMessage"), {
      inputValue: message.content || "",
      inputType: "textarea",
      confirmButtonText: homeT("actions.save"),
      cancelButtonText: homeT("actions.cancel"),
      inputValidator: (value) => Boolean(String(value || "").trim()) || homeT("messages.emptyMessage"),
    });
    const content = String(result.value || "").trim();
    if (!content || content === message.content) return;
    const res = await chatApi.editMessage(message.id, content, Number(message.version || 0));
    upsertMessage(res.data?.message || {
      ...message,
      content,
      editedAt: new Date().toISOString(),
      version: Number(message.version || 1) + 1,
    });
  } catch (error) {
    if (error === "cancel" || error === "close") return;
    showApiError(error);
  }
};

const recallExistingMessage = async (message) => {
  if (!canRecallMessage(message)) return;
  try {
    await ElMessageBox.confirm(
      homeT("messages.recallConfirm"),
      homeT("chat.recallMessage"),
      {
        type: "warning",
        confirmButtonText: homeT("chat.recallMessage"),
        cancelButtonText: homeT("actions.cancel"),
      },
    );
    const res = await chatApi.recallMessage(message.id);
    upsertMessage(res.data?.message || {
      ...message,
      content: "",
      attachments: [],
      deletedAt: new Date().toISOString(),
      deletedBy: currentUserid,
      isRecalled: true,
    });
  } catch (error) {
    if (error === "cancel" || error === "close") return;
    showApiError(error);
  }
};

const deleteExistingMessageForMe = async (message) => {
  if (!isPersistedMessage(message)) {
    const clientMessageId = messageClientId(message);
    if (!clientMessageId) return;
    const nextPending = { ...pendingMessages.value };
    delete nextPending[clientMessageId];
    pendingMessages.value = nextPending;
    persistPendingMessages();
    const dedupeKey = messageDedupeKey(message);
    messages.value = messages.value.filter((item) => messageDedupeKey(item) !== dedupeKey);
    return;
  }
  try {
    await ElMessageBox.confirm(
      homeT("messages.deleteForMeConfirm"),
      homeT("chat.deleteForMe"),
      {
        type: "warning",
        confirmButtonText: homeT("actions.remove"),
        cancelButtonText: homeT("actions.cancel"),
      },
    );
    await chatApi.deleteMessageForMe(message.id);
    messages.value = messages.value.filter((item) => item.id !== message.id);
  } catch (error) {
    if (error === "cancel" || error === "close") return;
    showApiError(error);
  }
};

const quickReactionEmojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"];

const messageReactionGroups = (message = {}) => normalizeReactionGroups(message, currentUserid);

const compactMessageReactions = (message = {}) => messageReactionGroups(message)
  .slice()
  .sort((left, right) => Number(right.count || 0) - Number(left.count || 0))
  .slice(0, 3);

const totalMessageReactions = (message = {}) => messageReactionGroups(message)
  .reduce((total, reaction) => total + Number(reaction.count || 0), 0);

const reactionUsers = (reaction = {}) => {
  const namedUsers = Array.isArray(reaction.users) ? reaction.users : [];
  const usersById = new Map(
    namedUsers
      .filter((user) => hasUserid(user?.userid))
      .map((user) => [normalizeUserid(user.userid), user]),
  );
  const userids = [...new Set([
    ...namedUsers.map((user) => normalizeUserid(user?.userid)),
    ...(reaction.userids || []).map(normalizeUserid),
  ].filter(Boolean))];

  return userids.map((userid) => {
    const namedUser = usersById.get(userid);
    const member = (activeConversation.value?.members || []).find((item) => useridsMatch(item.userid, userid));
    const isCurrentUser = useridsMatch(userid, currentUserid);
    return {
      userid,
      fullname: namedUser?.fullname
        || member?.nickname
        || member?.fullname
        || (isCurrentUser ? currentUser.value.fullname : "")
        || userid,
      avatar: namedUser?.avatar || member?.avatar || (isCurrentUser ? currentUser.value.avatar : "") || "",
    };
  });
};

const messageReadUsers = (message = {}) => {
  const receipts = Array.isArray(message.receipts)
    ? message.receipts
    : Array.isArray(message.readReceipts)
      ? message.readReceipts
      : [];
  const readReceipts = receipts.filter((receipt) => receipt?.readAt || receipt?.read_at);
  const receiptByUserid = new Map(
    readReceipts
      .filter((receipt) => hasUserid(receipt?.userid || receipt?.userId || receipt?.user_id))
      .map((receipt) => [
        normalizeUserid(receipt.userid || receipt.userId || receipt.user_id),
        receipt,
      ]),
  );
  const readBy = Array.isArray(message.readBy)
    ? message.readBy
    : Array.isArray(message.read_by)
      ? message.read_by
      : [];
  const userids = [...new Set([
    ...receiptByUserid.keys(),
    ...readBy.map((entry) => normalizeUserid(entry?.userid || entry)),
  ].filter(Boolean))];

  return userids.map((userid) => {
    const receipt = receiptByUserid.get(userid) || {};
    const member = (activeConversation.value?.members || []).find((item) => useridsMatch(item.userid, userid));
    return {
      userid,
      fullname: receipt.fullname
        || receipt.fullName
        || member?.nickname
        || member?.fullname
        || userid,
      avatar: receipt.avatar || member?.avatar || "",
      readAt: receipt.readAt || receipt.read_at || "",
    };
  });
};

const canShowMessageReaders = (message = {}) => activeConversation.value?.type === "group"
  && isOwnMessage(message)
  && messageReadUsers(message).length > 0;

const formatEditHistoryTime = (value) => {
  const parsed = dayjs(value);
  return parsed.isValid() ? parsed.format("DD/MM/YYYY HH:mm") : "";
};

const openMessageEditHistory = async (message) => {
  if (!isPersistedMessage(message)) return;
  editHistoryDialogVisible.value = true;
  editHistoryLoading.value = true;
  messageEditHistory.value = [];
  try {
    const response = await chatApi.getMessageEditHistory(message.id);
    messageEditHistory.value = response.data?.history || [];
  } catch (error) {
    editHistoryDialogVisible.value = false;
    showApiError(error);
  } finally {
    editHistoryLoading.value = false;
  }
};

const toggleReaction = async (message, emoji, reactedByMe) => {
  if (!isPersistedMessage(message) || !emoji || isMessageRecalled(message)) return;
  const currentReaction = messageReactionGroups(message).find((reaction) => reaction.emoji === emoji);
  const shouldRemove = reactedByMe ?? Boolean(currentReaction?.reactedByMe);
  const key = `${message.id}:${emoji}`;
  if (reactionPending.value[key]) return;
  reactionPending.value = { ...reactionPending.value, [key]: true };
  try {
    const res = shouldRemove
      ? await chatApi.removeReaction(message.id, emoji)
      : await chatApi.addReaction(message.id, emoji);
    if (res.data?.message) {
      upsertMessage(res.data.message);
    } else if (res.data?.reactions || res.data?.reactionSummary) {
      upsertMessage({
        ...message,
        reactions: res.data.reactions || res.data.reactionSummary,
      });
    } else {
      applyLocalReaction(message, emoji, shouldRemove);
    }
  } catch (error) {
    showApiError(error);
  } finally {
    const nextPending = { ...reactionPending.value };
    delete nextPending[key];
    reactionPending.value = nextPending;
  }
};

const applyLocalReaction = (message, emoji, remove) => {
  const groups = messageReactionGroups(message).map((reaction) => ({
    ...reaction,
    userids: [...reaction.userids],
    users: [...(reaction.users || [])],
  }));
  const index = groups.findIndex((reaction) => reaction.emoji === emoji);
  if (remove && index >= 0) {
    groups[index].userids = groups[index].userids.filter((userid) => !useridsMatch(userid, currentUserid));
    groups[index].users = groups[index].users.filter((user) => !useridsMatch(user.userid, currentUserid));
    groups[index].count = Math.max(0, groups[index].count - 1);
    groups[index].reactedByMe = false;
    if (!groups[index].count) groups.splice(index, 1);
  } else if (!remove) {
    if (index >= 0) {
      if (!groups[index].userids.includes(currentUserid)) groups[index].userids.push(currentUserid);
      if (!groups[index].users.some((user) => useridsMatch(user.userid, currentUserid))) {
        groups[index].users.push({ ...currentUser.value });
      }
      groups[index].count = Math.max(groups[index].count + 1, groups[index].userids.length);
      groups[index].reactedByMe = true;
    } else {
      groups.push({
        emoji,
        count: 1,
        userids: [currentUserid],
        users: [{ ...currentUser.value }],
        reactedByMe: true,
      });
    }
  }
  upsertMessage({ ...message, reactions: groups });
};

const applyReactionEvent = (event = {}) => {
  if (event.message?.id) {
    if (event.message.conversationId === activeConversationId.value) upsertMessage(event.message);
    return;
  }
  const message = messages.value.find((item) => item.id === event.messageId);
  if (!message) return;
  const reactions = event.payload?.reactions || event.payload?.reactionSummary || event.payload?.reaction_summary;
  if (reactions) upsertMessage({ ...message, reactions });
};

const receiptUserids = (message = {}, field) => {
  const values = message[field] || [];
  return values.map((value) => String(value?.userid || value || "")).filter(Boolean);
};

const messageRecipientCount = (message = {}) => {
  const summaryTotal = Number(
    message.receiptSummary?.totalRecipients
    || message.receipt_summary?.total_recipients
    || 0,
  );
  if (summaryTotal > 0) return summaryTotal;
  const conversation = conversations.value.find((item) => item.id === message.conversationId);
  const memberRecipients = (conversation?.members || [])
    .filter((member) => !useridsMatch(member.userid, message.senderUserid))
    .length;
  return memberRecipients || Math.max(1, Number(conversation?.memberCount || 0) - 1);
};

const applyReadReceipt = (event = {}) => {
  if (event.message?.id) upsertMessage(event.message);
  const conversationId = event.conversationId;
  const readerUserid = event.readerUserid || event.userid || event.payload?.userid;
  const lastReadMessageId = Number(
    event.lastReadMessageId
    || event.payload?.readState?.lastReadMessageId
    || event.payload?.read_state?.last_read_message_id
    || event.messageId
    || 0,
  );
  if (!conversationId || !lastReadMessageId) return;
  if (useridsMatch(readerUserid, currentUserid)) {
    const serverReadState = event.payload?.readState || event.payload?.read_state || {};
    applyConversationReadState(conversationId, {
      ...serverReadState,
      lastReadMessageId: serverReadState.lastReadMessageId
        || serverReadState.last_read_message_id
        || lastReadMessageId,
    });
    return;
  }
  messages.value = messages.value.map((message) => {
    if (!isPersistedMessage(message) || message.conversationId !== conversationId || !isOwnMessage(message) || Number(message.id) > lastReadMessageId) {
      return message;
    }
    return applyMessageReceipt(message, {
      kind: "read",
      userid: readerUserid,
      occurredAt: event.payload?.readAt || event.payload?.read_at || event.serverTimestamp,
      totalRecipients: messageRecipientCount(message),
    });
  });
};

const applyDeliveryReceipt = (event = {}) => {
  if (event.message?.id) upsertMessage(event.message);
  const conversationId = event.conversationId;
  const userid = event.userid || event.payload?.userid;
  const deliveredMessageId = Number(event.deliveredMessageId || event.messageId || 0);
  if (!conversationId || !deliveredMessageId || useridsMatch(userid, currentUserid)) return;
  messages.value = messages.value.map((message) => {
    if (!isPersistedMessage(message) || message.conversationId !== conversationId || !isOwnMessage(message) || Number(message.id) > deliveredMessageId) {
      return message;
    }
    return applyMessageReceipt(message, {
      kind: "delivered",
      userid,
      occurredAt: event.payload?.deliveredAt || event.payload?.delivered_at || event.serverTimestamp,
      totalRecipients: messageRecipientCount(message),
    });
  });
};

const messageStatusLabel = (message = {}) => {
  const state = messageDeliveryState(message);
  if (state === "sending") return homeT("chat.statusSending");
  if (state === "failed") return homeT("chat.statusFailed");
  const group = activeConversation.value?.type === "group";
  if (group) {
    const readCount = Number(
      message.readCount
      || message.receiptSummary?.readRecipients
      || message.receipt_summary?.read_recipients
      || (message.receipts || []).filter((receipt) => receipt.readAt || receipt.read_at).length
      || receiptUserids(message, "readBy").length
      || 0,
    );
    if (readCount) return homeT("chat.statusReadBy", { count: readCount });
    const deliveredCount = Number(
      message.deliveredCount
      || message.receiptSummary?.deliveredRecipients
      || message.receipt_summary?.delivered_recipients
      || (message.receipts || []).filter((receipt) => receipt.deliveredAt || receipt.delivered_at).length
      || receiptUserids(message, "deliveredTo").length
      || 0,
    );
    if (deliveredCount) return homeT("chat.statusDeliveredTo", { count: deliveredCount });
  }
  return homeT(`chat.status${state.charAt(0).toUpperCase()}${state.slice(1)}`);
};

const conversationUserSettings = (conversation = {}) => {
  const settings = conversation.mySettings || conversation.userSettings || {};
  return {
    muteUntil: settings.muteUntil ?? settings.mute_until ?? conversation.muteUntil ?? conversation.mute_until ?? null,
    pinnedAt: settings.pinnedAt ?? settings.pinned_at ?? conversation.pinnedAt ?? conversation.pinned_at ?? null,
    archivedAt: settings.archivedAt ?? settings.archived_at ?? conversation.archivedAt ?? conversation.archived_at ?? null,
  };
};

const isConversationMuted = (conversation = {}) => {
  const muteUntil = conversationUserSettings(conversation).muteUntil;
  return Boolean(muteUntil && dayjs(muteUntil).isAfter(dayjs()));
};

const isConversationPinned = (conversation = {}) => Boolean(conversationUserSettings(conversation).pinnedAt);

const isConversationArchived = (conversation = {}) => Boolean(conversationUserSettings(conversation).archivedAt);

const sortConversationsForDisplay = (items = []) => items
  .map((conversation, index) => ({ conversation, index }))
  .sort((first, second) => {
    const archivedDiff = Number(isConversationArchived(first.conversation)) - Number(isConversationArchived(second.conversation));
    if (archivedDiff !== 0) return archivedDiff;
    const pinnedDiff = Number(isConversationPinned(second.conversation)) - Number(isConversationPinned(first.conversation));
    if (pinnedDiff !== 0) return pinnedDiff;
    return first.index - second.index;
  })
  .map(({ conversation }) => conversation);

const applyConversationUserSettings = (conversationId, settings = {}) => {
  if (!conversationId) return;
  conversations.value = conversations.value.map((conversation) => (
    conversation.id === conversationId
      ? {
          ...conversation,
          ...(() => {
            const current = conversationUserSettings(conversation);
            const settingValue = (camelKey, snakeKey) => {
              if (Object.prototype.hasOwnProperty.call(settings, camelKey)) return settings[camelKey];
              if (Object.prototype.hasOwnProperty.call(settings, snakeKey)) return settings[snakeKey];
              return current[camelKey];
            };
            const nextSettings = {
              muteUntil: settingValue("muteUntil", "mute_until"),
              pinnedAt: settingValue("pinnedAt", "pinned_at"),
              archivedAt: settingValue("archivedAt", "archived_at"),
            };
            return { ...nextSettings, mySettings: nextSettings };
          })(),
        }
      : conversation
  ));
  conversations.value = sortConversationsForDisplay(conversations.value);
};

const saveConversationUserSettings = async (payload) => {
  if (!activeConversationId.value || settingsSaving.value) return;
  const conversationId = activeConversationId.value;
  try {
    settingsSaving.value = true;
    const res = await chatApi.updateConversationUserSettings(conversationId, payload);
    const settings = {
      ...payload,
      ...(res.data?.settings || res.data?.userSettings || res.data?.conversation?.mySettings || {}),
    };
    applyConversationUserSettings(conversationId, settings);
  } catch (error) {
    showApiError(error);
  } finally {
    settingsSaving.value = false;
  }
};

const toggleConversationMute = () => {
  const muted = isConversationMuted(activeConversation.value);
  void saveConversationUserSettings({ muteUntil: muted ? null : dayjs().add(8, "hour").toISOString() });
};

const toggleConversationPin = () => {
  const pinned = isConversationPinned(activeConversation.value);
  void saveConversationUserSettings({ pinnedAt: pinned ? null : new Date().toISOString() });
};

const toggleConversationArchive = () => {
  const archived = isConversationArchived(activeConversation.value);
  void saveConversationUserSettings({ archivedAt: archived ? null : new Date().toISOString() });
};

const applyConversationSettingsEvent = (event = {}) => {
  const userid = event.userid || event.payload?.userid;
  if (userid && !useridsMatch(userid, currentUserid)) return;
  const settings = event.payload?.settings || event.payload?.userSettings || event.payload;
  applyConversationUserSettings(event.conversationId, settings);
  void loadConversations(false, { silent: true });
};

const copyMessage = async (message = {}) => {
  const text = copyableMessageText(message);
  if (!text) {
    ElMessage.warning(homeT("messages.noMessageToCopy"));
    return;
  }

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
    } else {
      const textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
    }
    ElMessage.success(homeT("messages.messageCopied"));
  } catch {
    ElMessage.error(homeT("messages.copyFailed"));
  }
};

const resetPollForm = () => {
  pollForm.value = {
    question: "",
    options: ["", ""],
    allowCustomOptions: false,
    allowMultiple: false,
    showVoters: true,
  };
};

const openPollDialog = () => {
  if (activeConversation.value?.type !== "group") {
    ElMessage.warning(homeT("messages.groupOnlyPoll"));
    return;
  }
  resetPollForm();
  pollDialogVisible.value = true;
};

const addPollOption = () => {
  if (pollForm.value.options.length >= 20) return;
  pollForm.value.options.push("");
};

const removePollOption = (index) => {
  if (pollForm.value.options.length <= 2) return;
  pollForm.value.options.splice(index, 1);
};

const normalizedPollOptions = () =>
  pollForm.value.options
    .map((option) => option.trim())
    .filter(Boolean);

const submitPoll = async () => {
  if (!activeConversationId.value || pollSubmitting.value) return;
  if (activeConversation.value?.type !== "group") {
    ElMessage.warning(homeT("messages.groupOnlyPoll"));
    return;
  }

  const question = pollForm.value.question.trim();
  const options = normalizedPollOptions();
  if (!question) {
    ElMessage.warning(homeT("messages.enterPollQuestion"));
    return;
  }
  if (new Set(options.map((option) => option.toLowerCase())).size !== options.length) {
    ElMessage.warning(homeT("messages.duplicatePollOption"));
    return;
  }
  if (options.length < 2) {
    ElMessage.warning(homeT("messages.enterPollOptions"));
    return;
  }

  try {
    pollSubmitting.value = true;
    const res = await chatApi.createPoll(activeConversationId.value, {
      question,
      options,
      allowCustomOptions: pollForm.value.allowCustomOptions,
      allowMultiple: pollForm.value.allowMultiple,
      showVoters: pollForm.value.showVoters,
    });
    if (res.data?.message) {
      upsertMessage(res.data.message);
    }
    pollDialogVisible.value = false;
    resetPollForm();
    await loadConversations(false);
    await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    pollSubmitting.value = false;
  }
};

const setPollVoting = (messageId, isVoting) => {
  const next = { ...pollVotingMessageIds.value };
  if (isVoting) {
    next[messageId] = true;
  } else {
    delete next[messageId];
  }
  pollVotingMessageIds.value = next;
};

const upsertMessage = (message) => {
  if (!message?.id && !messageClientId(message)) return;
  const clientKey = messageDedupeKey(message);
  const index = messages.value.findIndex((item) => (
    (message.id && item.id === message.id)
    || (clientKey && messageDedupeKey(item) === clientKey)
  ));
  if (index >= 0) {
    const next = { ...messages.value[index], ...message };
    if (isPersistedMessage(message)) delete next._sendState;
    messages.value.splice(index, 1, next);
    messages.value = sortMessagesForDisplay(messages.value);
    return;
  }
  messages.value = sortMessagesForDisplay([...messages.value, message]);
};

const optimisticMessageFor = (conversationId, payload, overrides = {}) => ({
  id: `pending-${payload.clientMessageId}`,
  clientMessageId: payload.clientMessageId,
  conversationId,
  senderUserid: currentUserid,
  senderName: currentUser.value.fullname || currentUserid,
  senderAvatar: currentUser.value.avatar || "",
  type: payload.type || "text",
  content: payload.content || "",
  attachments: payload.attachments || [],
  replyTo: overrides.replyTo || null,
  forwardedFrom: overrides.forwardedFrom || null,
  createdAt: new Date().toISOString(),
  state: "sent",
  _sendState: "sending",
  ...overrides,
});

const setPendingMessageState = (clientMessageId, state, metadata = {}) => {
  const entry = pendingMessages.value[clientMessageId];
  if (!entry) return;
  const optimisticMessage = { ...entry.optimisticMessage, _sendState: state };
  pendingMessages.value = {
    ...pendingMessages.value,
    [clientMessageId]: { ...entry, ...metadata, optimisticMessage },
  };
  if (entry.conversationId === activeConversationId.value) upsertMessage(optimisticMessage);
  persistPendingMessages();
};

const queueMessageSend = async (conversationId, rawPayload, optimisticOverrides = {}) => {
  const clientMessageId = rawPayload.clientMessageId || createClientMessageId();
  const payload = { ...rawPayload, clientMessageId };
  const optimisticMessage = optimisticMessageFor(conversationId, payload, optimisticOverrides);
  pendingMessages.value = {
    ...pendingMessages.value,
    [clientMessageId]: {
      conversationId,
      clientMessageId,
      payload,
      optimisticMessage,
      createdAt: optimisticMessage.createdAt,
      retryable: true,
    },
  };
  persistPendingMessages();
  if (conversationId === activeConversationId.value) upsertMessage(optimisticMessage);
  return deliverPendingMessage(clientMessageId);
};

const pendingDeliveryIds = new Set();

const deliverPendingMessage = async (clientMessageId) => {
  const entry = pendingMessages.value[clientMessageId];
  if (!entry || pendingDeliveryIds.has(clientMessageId)) return null;
  pendingDeliveryIds.add(clientMessageId);
  setPendingMessageState(clientMessageId, "sending");
  try {
    const res = await chatApi.sendMessage(entry.conversationId, entry.payload);
    const responseMessage = res.data?.message;
    if (!responseMessage?.id) throw new Error("MESSAGE_RESPONSE_MISSING");
    const serverMessage = attachClientMessageId(responseMessage, clientMessageId);
    const nextPending = { ...pendingMessages.value };
    delete nextPending[clientMessageId];
    pendingMessages.value = nextPending;
    persistPendingMessages();
    updateMessageCursor(serverMessage);
    if (entry.conversationId === activeConversationId.value) upsertMessage(serverMessage);
    return serverMessage;
  } catch (error) {
    if (!pendingMessages.value[clientMessageId]) {
      const pendingKey = messageDedupeKey(entry.optimisticMessage);
      return messages.value.find((message) => messageDedupeKey(message) === pendingKey) || null;
    }
    setPendingMessageState(clientMessageId, "failed", {
      retryable: isRetryableSendError(error),
      lastFailureStatus: Number(error?.response?.status || 0),
      lastFailureCode: String(error?.code || error?.response?.data?.error || error?.message || ""),
    });
    throw error;
  } finally {
    pendingDeliveryIds.delete(clientMessageId);
  }
};

const retryPendingMessage = async (message) => {
  const clientMessageId = messageClientId(message);
  if (!clientMessageId || !pendingMessages.value[clientMessageId]) return;
  try {
    await deliverPendingMessage(clientMessageId);
    await loadConversations(false, { silent: true });
  } catch {
    ElMessage.error(homeT("messages.sendFailed"));
  }
};

const retryPendingMessages = async () => {
  if (!navigator.onLine) return;
  const clientMessageIds = Object.keys(pendingMessages.value);
  for (const clientMessageId of clientMessageIds) {
    if (pendingMessages.value[clientMessageId]?.retryable === false) continue;
    try {
      await deliverPendingMessage(clientMessageId);
    } catch {
      // Keep the exact clientMessageId in the durable outbox for a later retry.
    }
  }
};

const submitPollVote = async (message, optionIds, customOption = "") => {
  if (!message?.id || pollInteractionDisabled(message)) return;

  try {
    setPollVoting(message.id, true);
    const res = await chatApi.votePoll(message.id, { optionIds, customOption });
    if (res.data?.message) {
      upsertMessage(res.data.message);
    }
  } catch (error) {
    showApiError(error);
  } finally {
    setPollVoting(message.id, false);
  }
};

const closePoll = async (message) => {
  if (!canClosePoll(message) || pollVotingMessageIds.value[message.id]) return;

  try {
    setPollVoting(message.id, true);
    const res = await chatApi.closePoll(message.id);
    if (res.data?.message) {
      upsertMessage(res.data.message);
    }
  } catch (error) {
    showApiError(error);
  } finally {
    setPollVoting(message.id, false);
  }
};

const votePollOption = (message, option, event) => {
  if (!message?.poll || !option?.id) return;
  const selected = new Set(message.poll.myOptionIds || []);
  if (message.poll.allowMultiple) {
    if (event?.target?.checked) {
      selected.add(option.id);
    } else {
      selected.delete(option.id);
    }
  } else {
    selected.clear();
    selected.add(option.id);
  }
  void submitPollVote(message, Array.from(selected));
};

const submitCustomPollOption = (message) => {
  const customOption = String(pollCustomInputs.value[message.id] || "").trim();
  if (!customOption) return;
  const optionIds = message.poll?.allowMultiple ? [...(message.poll.myOptionIds || [])] : [];
  pollCustomInputs.value = { ...pollCustomInputs.value, [message.id]: "" };
  void submitPollVote(message, optionIds, customOption);
};

const isPollOptionSelected = (message = {}, option = {}) =>
  (message.poll?.myOptionIds || []).includes(option.id);

const pollInteractionDisabled = (message = {}) =>
  Boolean(message.poll?.isClosed || pollVotingMessageIds.value[message.id]);

const canClosePoll = (message = {}) =>
  message.type === "poll" && useridsMatch(message.poll?.createdBy, currentUserid) && !message.poll?.isClosed;

const pollOptionPercent = (poll = {}, option = {}) => {
  const totalOptionVotes = (poll.options || []).reduce((total, item) => total + Number(item.voteCount || 0), 0);
  if (!totalOptionVotes) return 0;
  return Math.round((Number(option.voteCount || 0) / totalOptionVotes) * 100);
};

const pollVoterNames = (option = {}) =>
  (option.voters || [])
    .map((voter) => voter.fullname || voter.userid)
    .filter(Boolean)
    .join(", ");

const pollMetaLabel = (poll = {}) => {
  const voteCount = Number(poll.totalVotes || 0);
  const mode = poll.allowMultiple ? homeT("poll.multipleChoice") : homeT("poll.singleChoice");
  return `${homeT("poll.voteCount", { count: voteCount })} · ${mode}`;
};

const openForwardDialog = (message) => {
  if (message?.type === "poll" || message?.type === "system") {
    ElMessage.warning(homeT("messages.pollForwardUnsupported"));
    return;
  }
  forwardingMessage.value = message;
  forwardTargetConversationId.value = conversations.value.find((conversation) => conversation.id !== activeConversationId.value)?.id
    || activeConversationId.value;
  forwardDialogVisible.value = true;
};

const submitForward = async () => {
  if (!forwardingMessage.value || !forwardTargetConversationId.value || sending.value) return;

  const message = forwardingMessage.value;
  try {
    sending.value = true;
    const serverMessage = await queueMessageSend(forwardTargetConversationId.value, {
      type: message.type,
      content: message.content || "",
      forwardedFromMessageId: message.id,
      attachments: cloneAttachments(message.attachments || []),
    }, {
      forwardedFrom: toMessageReference(message),
    });
    forwardDialogVisible.value = false;
    forwardingMessage.value = null;
    if (forwardTargetConversationId.value === activeConversationId.value && serverMessage) {
      upsertMessage(serverMessage);
      await scrollToBottom();
    }
    await loadConversations(false);
    ElMessage.success(homeT("messages.messageForwarded"));
  } catch (error) {
    showApiError(error);
  } finally {
    sending.value = false;
  }
};

const sendCurrentMessage = async () => {
  if (!activeConversationId.value || sending.value || uploading.value || isRecording.value) return;

  const content = composerText.value.trim();
  const hasAttachments = pendingAttachments.value.length > 0;
  const type = !hasAttachments && isLinkMessageContent(content) ? "link" : hasAttachments ? pendingAttachmentType.value : "text";

  if (!content && !hasAttachments) {
    ElMessage.warning(homeT("messages.emptyMessage"));
    return;
  }

  const conversationId = activeConversationId.value;
  const replySnapshot = replyingTo.value ? { ...replyingTo.value } : null;
  const attachmentSnapshot = pendingAttachments.value.map((attachment) => ({ ...attachment }));
  composerText.value = "";
  stopLocalTyping(true, conversationId);
  cancelReply();
  pendingAttachments.value = [];

  try {
    sending.value = true;
    await queueMessageSend(conversationId, {
      type,
      content,
      replyToMessageId: replySnapshot?.id || 0,
      attachments: attachmentSnapshot,
    }, {
      replyTo: replySnapshot,
    });
    await loadConversations(false);
    await scrollToBottom();
  } catch (error) {
    ElMessage.error(homeT("messages.sendFailed"));
  } finally {
    sending.value = false;
  }
};

const scrollToBottom = async () => {
  showLatestButton.value = false;
  newMessagesBelowCount.value = 0;
  await nextTick();
  const el = messageListRef.value;
  if (!el) return;

  const scroll = () => {
    el.scrollTop = el.scrollHeight;
  };

  scroll();
  window.requestAnimationFrame(scroll);
  window.setTimeout(scroll, 120);
};

const isMessageListNearBottom = () => {
  const el = messageListRef.value;
  if (!el) return true;
  return el.scrollHeight - el.scrollTop - el.clientHeight < 140;
};

const registerNewMessagesBelow = (count = 1) => {
  if (count <= 0) return;
  newMessagesBelowCount.value += count;
  showLatestButton.value = true;
};

const scrollToMessage = async (messageId) => {
  await nextTick();
  const target = document.getElementById(`message-${messageId}`);
  if (!target) return;
  target.scrollIntoView({ behavior: "smooth", block: "center" });
  target.classList.add("highlight");
  window.setTimeout(() => target.classList.remove("highlight"), 1400);
};

const handleLogout = async () => {
  disconnectRealtime();
  try {
    await chatApi.unregisterDeviceToken(currentDeviceId);
  } catch {
    // Logout remains available when the device is offline.
  }
  localStorage.removeItem("user_token");
  localStorage.removeItem("userid");
  localStorage.removeItem("fullname");
  localStorage.removeItem("account_id");
  router.push("/login");
};

const isOwnMessage = (message) => useridsMatch(message.senderUserid, currentUserid);

const isCenteredMessage = (message = {}) => message.type === "system" || message.type === "poll";

const toMessageReference = (message = {}) => ({
  id: message.id,
  senderUserid: message.senderUserid,
  senderName: message.senderName,
  type: message.type,
  content: message.content || "",
});

const cloneAttachments = (attachments = []) =>
  attachments.map((attachment) => ({
    fileName: attachment.fileName,
    fileUrl: attachment.fileUrl,
    fileSize: attachment.fileSize,
    mimeType: attachment.mimeType,
    relativePath: attachment.relativePath,
  }));

const copyableMessageText = (message = {}) => {
  if (message.type === "call") return callMessageTitle(message);
  const content = String(message.content || "").trim();
  if (content) return content;

  const attachmentText = (message.attachments || [])
    .map((attachment) => {
      return attachment.relativePath || attachment.fileName || "";
    })
    .filter(Boolean)
    .join("\n");

  return attachmentText || messageReferencePreview(message);
};

const callMessageInfo = (message = {}) => {
  let parsed = {};
  try {
    const content = String(message.content || "").trim();
    if (content.startsWith("{")) parsed = JSON.parse(content);
  } catch (_) {
    parsed = {};
  }

  const duration = Number(parsed.duration);
  return {
    status: parsed.status === "missed" ? "missed" : "completed",
    duration: Number.isFinite(duration) && duration > 0 ? Math.floor(duration) : 0,
  };
};

const callMessageDirection = (message = {}) =>
  useridsMatch(message.senderUserid, currentUserid) ? "outgoing" : "incoming";

const callMessageCopy = (key) => {
  const labels = {
    vi: {
      incoming: "Cu\u1ed9c g\u1ecd\u0069 \u0111\u1ebfn",
      outgoing: "Cu\u1ed9c g\u1ecd\u0069 \u0111\u0069",
      missed: "Cu\u1ed9c g\u1ecd\u0069 nh\u1ee1",
      completed: "\u0110\u00e3 k\u1ebft th\u00fac",
      notAnswered: "Kh\u00f4ng tr\u1ea3 l\u1eddi",
      call: "Cu\u1ed9c g\u1ecd\u0069",
    },
    en: {
      incoming: "Incoming call",
      outgoing: "Outgoing call",
      missed: "Missed call",
      completed: "Ended",
      notAnswered: "Not answered",
      call: "Call",
    },
    cn: {
      incoming: "\u6765\u7535",
      outgoing: "\u62e8\u51fa\u7535\u8bdd",
      missed: "\u672a\u63a5\u6765\u7535",
      completed: "\u5df2\u7ed3\u675f",
      notAnswered: "\u65e0\u4eba\u63a5\u542c",
      call: "\u7535\u8bdd",
    },
  };
  return labels[locale.value]?.[key] || labels.en[key] || labels.en.call;
};

const callMessageTitle = (message = {}) => {
  const info = callMessageInfo(message);
  if (info.status === "missed") return callMessageCopy("missed");
  return callMessageCopy(callMessageDirection(message));
};

const callMessageStatus = (message = {}) => {
  const info = callMessageInfo(message);
  return info.status === "missed" ? callMessageCopy("notAnswered") : callMessageCopy("completed");
};

const callMessageIcon = (message = {}) => {
  const info = callMessageInfo(message);
  if (info.status === "missed") return PhoneMissed;
  return callMessageDirection(message) === "incoming" ? PhoneIncoming : PhoneOutgoing;
};

const messageReferencePreview = (message = {}) => {
  if (message.type === "system") return message.content || homeT("previews.system");
  if (message.type === "poll") return message.content || homeT("previews.poll");
  if (message.type === "call") return callMessageTitle(message);
  if (message.content) return message.content;
  if (message.type === "voice") return homeT("previews.voice");
  if (message.type === "folder") return homeT("previews.folderAttachment");
  if (message.type === "file") return homeT("previews.fileAttachment");
  if (message.type === "link") return homeT("previews.link");
  return homeT("previews.message");
};

const messageTextParts = (content = "") => {
  const labels = mentionLabels();
  if (!content || !labels.length) return [{ text: content, isMention: false, member: null }];

  const parts = [];
  const lowerContent = content.toLowerCase();
  let cursor = 0;

  while (cursor < content.length) {
    let nextMatch = null;
    for (const label of labels) {
      const index = findMentionIndex(content, lowerContent, label, cursor);
      if (index < 0) continue;
      if (!nextMatch || index < nextMatch.index || (index === nextMatch.index && label.text.length > nextMatch.text.length)) {
        nextMatch = { ...label, index };
      }
    }

    if (!nextMatch) {
      parts.push({ text: content.slice(cursor), isMention: false, member: null });
      break;
    }

    if (nextMatch.index > cursor) {
      parts.push({ text: content.slice(cursor, nextMatch.index), isMention: false, member: null });
    }
    parts.push({
      text: content.slice(nextMatch.index, nextMatch.index + nextMatch.text.length),
      isMention: true,
      member: nextMatch.member || null,
    });
    cursor = nextMatch.index + nextMatch.text.length;
  }

  return parts;
};

const mentionLabels = () => {
  const members = activeConversation.value?.members || [];
  const labels = [];
  const seen = new Set();

  if (isGroupConversation(activeConversation.value)) {
    labels.push({ text: `@${allMentionLabel}`, lower: `@${allMentionLabel.toLowerCase()}`, member: null });
    seen.add(`@${allMentionLabel.toLowerCase()}`);
  }

  members.forEach((member) => {
    [`@${displayName(member)}`, `@${member.fullname}`, `@${member.userid}`].forEach((label) => {
      const normalized = label.trim();
      if (normalized.length <= 1 || seen.has(normalized.toLowerCase())) return;
      seen.add(normalized.toLowerCase());
      labels.push({ text: normalized, lower: normalized.toLowerCase(), member });
    });
  });

  return labels.sort((first, second) => second.text.length - first.text.length);
};

const hasMentionBoundary = (content, start, end) => {
  const before = start === 0 ? "" : content[start - 1];
  const after = end >= content.length ? "" : content[end];
  const beforeOk = !before || /\s|[([{]/.test(before);
  const afterOk = !after || /\s|[.,!?;:)\]}]/.test(after);
  return beforeOk && afterOk;
};

const findMentionIndex = (content, lowerContent, label, fromIndex) => {
  let index = lowerContent.indexOf(label.lower, fromIndex);
  while (index >= 0) {
    if (hasMentionBoundary(content, index, index + label.text.length)) return index;
    index = lowerContent.indexOf(label.lower, index + 1);
  }
  return -1;
};

const imageAttachments = (message) =>
  (message.attachments || []).filter((attachment) => isImageAttachment(attachment));

const videoAttachments = (message) =>
  (message.attachments || []).filter((attachment) => isVideoAttachment(attachment));

const voiceAttachments = (message) =>
  message.type === "voice"
    ? (message.attachments || []).filter((attachment) => isAudioAttachment(attachment))
    : [];

const fileAttachments = (message) =>
  (message.attachments || []).filter(
    (attachment) => !isImageAttachment(attachment) && !isVideoAttachment(attachment) && !(message.type === "voice" && isAudioAttachment(attachment)),
  );

const isImageAttachment = (attachment) => {
  const mimeType = (attachment.mimeType || "").toLowerCase();
  return mimeType.startsWith("image/") || ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"].includes(fileExt(attachment));
};

const isAudioAttachment = (attachment) => {
  const mimeType = (attachment.mimeType || "").toLowerCase();
  if (mimeType.startsWith("video/")) return false;
  return mimeType.startsWith("audio/") || ["mp3", "wav", "m4a", "aac", "flac", "ogg", "oga", "webm"].includes(fileExt(attachment));
};

const isVideoAttachment = (attachment) => {
  const mimeType = (attachment.mimeType || "").toLowerCase();
  return mimeType.startsWith("video/") || ["mp4", "mov", "avi", "mkv", "webm"].includes(fileExt(attachment));
};

const fileExt = (attachment) => {
  const name = (attachment.fileName || attachment.relativePath || "").toLowerCase();
  const ext = name.split(".").pop();
  return ext && ext !== name ? ext : "";
};

const fileKind = (attachment, messageType = "file") => {
  if (messageType === "voice") return "voice";
  if (messageType === "folder") return "folder";
  if (isImageAttachment(attachment)) return "image";
  if (isAudioAttachment(attachment)) return "audio";
  const ext = fileExt(attachment);
  if (["doc", "docx"].includes(ext)) return "word";
  if (["xls", "xlsx", "csv"].includes(ext)) return "excel";
  if (["ppt", "pptx"].includes(ext)) return "ppt";
  if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) return "archive";
  if (["mp4", "mov", "avi", "mkv", "webm"].includes(ext)) return "video";
  if (["js", "ts", "go", "json", "html", "css", "vue", "xml", "sql"].includes(ext)) return "code";
  if (ext === "pdf") return "pdf";
  return "file";
};

const fileKindLabel = (attachment, messageType = "file") => {
  const kind = fileKind(attachment, messageType);
  const labels = {
    archive: homeT("fileKinds.archive"),
    audio: homeT("fileKinds.audio"),
    code: homeT("fileKinds.code"),
    excel: "Excel",
    file: fileExt(attachment).toUpperCase() || homeT("fileKinds.file"),
    folder: homeT("fileKinds.folder"),
    image: homeT("fileKinds.image"),
    pdf: "PDF",
    ppt: "PowerPoint",
    video: "Video",
    voice: homeT("previews.voice"),
    word: "Word",
  };
  return labels[kind] || homeT("fileKinds.file");
};

const fileBadge = (attachment, messageType = "file") => {
  const kind = fileKind(attachment, messageType);
  if (kind === "folder") return "";
  if (kind === "voice") return "VOC";
  if (kind === "audio") return "AUD";
  if (kind === "video") return "VID";
  if (kind === "image") return "IMG";
  if (kind === "archive") return "ZIP";
  if (kind === "word") return "DOC";
  if (kind === "excel") return "XLS";
  if (kind === "ppt") return "PPT";
  if (kind === "code") return "CODE";
  if (kind === "pdf") return "PDF";
  return fileExt(attachment).slice(0, 4).toUpperCase();
};

const fileIcon = (attachment, messageType = "file") => {
  const kind = fileKind(attachment, messageType);
  const icons = {
    archive: FileArchive,
    audio: FileAudio,
    code: FileCode,
    excel: FileSpreadsheet,
    file: File,
    folder: Folder,
    image: FileImage,
    pdf: FileText,
    ppt: Presentation,
    video: FileVideo,
    voice: FileAudio,
    word: FileText,
  };
  return icons[kind] || FileText;
};

const folderNameFromPath = (path = "") => path.split("/").filter(Boolean)[0] || "";

const displayName = (user = {}) => user.nickname || user.fullname || user.userid || "";

function normalizeDirectoryText(value = "") {
  return String(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .toLocaleLowerCase("vi")
    .trim();
}

function directoryLetter(name = "") {
  const normalized = normalizeDirectoryText(name);
  const first = normalized.charAt(0).toUpperCase();
  return /^[A-Z]$/.test(first) ? first : "#";
}

const initials = (name = "") => {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (!words.length) return "YS";
  return words
    .slice(-2)
    .map((word) => word[0])
    .join("")
    .toUpperCase();
};

const lastMessagePreview = (conversation) => {
  const message = conversation.lastMessage;
  if (!message) return homeT("previews.noMessages");
  const prefix = useridsMatch(message.senderUserid, currentUserid) ? homeT("previews.youPrefix") : "";
  if (message.type === "call") return `${prefix}${callMessageTitle(message)}`;
  if (message.type === "voice") return `${prefix}${homeT("previews.voice")}`;
  if (message.type === "file") return `${prefix}${homeT("previews.fileAttachment")}`;
  if (message.type === "folder") return `${prefix}${homeT("previews.folderAttachment")}`;
  if (message.type === "link") return `${prefix}${homeT("previews.link")}`;
  if (message.type === "system") return message.content || homeT("previews.system");
  if (message.type === "poll") return `${prefix}${message.content || homeT("previews.poll")}`;
  return `${prefix}${message.content || ""}`;
};

const conversationTime = (conversation) => {
  const time = conversation.lastMessage?.createdAt || conversation.updatedAt;
  if (!time) return "";
  const value = dayjs(time);
  return value.isSame(dayjs(), "day") ? value.format("HH:mm") : value.format("DD/MM");
};

const formatTime = (time) => (time ? dayjs(time).format("HH:mm") : "");

const storageDateLabel = (time) => {
  const value = dayjs(time);
  if (!value.isValid()) return homeT("info.unknownDate");
  if (locale.value === "vi") return `Ngày ${value.format("D")} Tháng ${value.format("M")}`;
  if (locale.value === "cn") return value.format("M月D日");
  return value.format("MMMM D");
};

const groupStorageItems = (items = [], getDate = () => "") => {
  const groups = new Map();
  items.forEach((item) => {
    const date = dayjs(getDate(item));
    const key = date.isValid() ? date.format("YYYY-MM-DD") : "unknown";
    if (!groups.has(key)) {
      groups.set(key, {
        key,
        label: date.isValid() ? storageDateLabel(date) : homeT("info.unknownDate"),
        sort: date.isValid() ? date.valueOf() : 0,
        items: [],
      });
    }
    groups.get(key).items.push(item);
  });

  return Array.from(groups.values()).sort((first, second) => second.sort - first.sort);
};

const storageItemKey = (item = {}) => item.fileUrl || `${item.id}-${item.content || ""}`;

const formatDuration = (seconds = 0) => {
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(remainingSeconds).padStart(2, "0")}`;
};

const formatBytes = (bytes = 0) => {
  if (!bytes) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`;
};

const downloadFileName = (attachment = {}) => attachment.fileName || attachment.relativePath?.split("/").pop() || "";

const safeLink = (value) => {
  if (/^https?:\/\//i.test(value)) return value;
  return `https://${value}`;
};

const isLinkMessageContent = (value = "") => {
  const content = value.trim();
  if (!content || /\s/.test(content)) return false;
  const hasProtocol = /^https?:\/\//i.test(content);

  try {
    const url = new URL(hasProtocol ? content : `https://${content}`);
    if (!["http:", "https:"].includes(url.protocol)) return false;
    if (!url.hostname) return false;
    return hasProtocol || url.hostname.includes(".");
  } catch {
    return false;
  }
};

const cssUrl = (value = "") => value.replace(/["\\]/g, "\\$&");

const showApiError = (error) => {
  const code = error?.response?.data?.error;
  if (code === "UNAUTHORIZED") {
    handleLogout();
    return;
  }
  if (code === "INVALID_CREDENTIALS") {
    ElMessage.error(homeT("messages.invalidCurrentPassword"));
    return;
  }
  const translated = code ? t(`api_errors.${code}`) : "";
  ElMessage.error(translated && translated !== `api_errors.${code}` ? translated : code || homeT("messages.genericError"));
};
</script>

<style scoped>
.chat-shell {
  --brand: #0891b2;
  --brand-dark: #0e7490;
  --brand-focus: #22d3ee;
  --brand-soft: #cffafe;
  --brand-softest: #ecfeff;
  --brand-border: #a5f3fc;
  --brand-tint: rgba(8, 145, 178, 0.12);
  --brand-overlay: rgba(236, 254, 255, 0.92);
  width: 100vw;
  height: 100vh;
  display: grid;
  grid-template-columns: 72px minmax(300px, 360px) minmax(0, 1fr) minmax(260px, 318px);
  overflow: hidden;
  background: #eef2f7;
  color: #172033;
  position: relative;
}

button,
input,
textarea {
  font: inherit;
}

button {
  border: 0;
}

a {
  text-decoration: none;
}

.drop-overlay {
  position: fixed;
  inset: 12px;
  z-index: 10000;
  display: grid;
  align-content: center;
  justify-items: center;
  gap: 8px;
  border: 2px dashed var(--brand);
  border-radius: 8px;
  background: var(--brand-overlay);
  color: var(--brand-dark);
  pointer-events: none;
}

.drop-overlay span {
  color: #506176;
}

.notification-stack {
  position: fixed;
  right: 18px;
  bottom: 18px;
  z-index: 12000;
  display: grid;
  gap: 10px;
  width: min(360px, calc(100vw - 28px));
}

.message-toast {
  min-width: 0;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 10px;
  align-items: center;
  padding: 10px;
  border-radius: 8px;
  background: #ffffff;
  color: #172033;
  box-shadow: 0 18px 50px rgba(15, 23, 42, 0.22);
  border: 1px solid #dbe7f6;
  cursor: pointer;
  text-align: left;
}

.message-toast span {
  min-width: 0;
  display: grid;
  gap: 1px;
}

.message-toast strong,
.message-toast small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.message-toast small {
  color: #64748b;
}

.call-panel {
  position: fixed;
  top: 18px;
  right: 18px;
  z-index: 13000;
  width: min(380px, calc(100vw - 28px));
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 12px;
  padding: 12px;
  border-radius: 8px;
  background: #ffffff;
  color: #172033;
  border: 1px solid #dbe7f6;
  box-shadow: 0 18px 50px rgba(15, 23, 42, 0.24);
}

.call-panel.video {
  width: min(720px, calc(100vw - 28px));
  background: #0f172a;
  color: #fff;
}

.call-video-stage {
  position: relative;
  grid-column: 1 / -1;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border-radius: 7px;
  background: #020617;
}

.call-video-remote {
  width: 100%;
  height: 100%;
  display: block;
  object-fit: cover;
}

.call-video-placeholder {
  position: absolute;
  inset: 0;
  display: grid;
  place-content: center;
  gap: 8px;
  color: #cbd5e1;
  text-align: center;
}

.call-video-local {
  position: absolute;
  right: 10px;
  bottom: 10px;
  width: min(28%, 170px);
  aspect-ratio: 3 / 4;
  border: 2px solid rgba(255, 255, 255, 0.78);
  border-radius: 7px;
  background: #111827;
  object-fit: cover;
  transform: scaleX(-1);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35);
}

.call-panel.video .call-peer small {
  color: #cbd5e1;
}

.call-peer {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 10px;
}

.call-peer > span:last-child {
  min-width: 0;
  display: grid;
  gap: 1px;
}

.call-peer strong,
.call-peer small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.call-peer small {
  color: #64748b;
  font-size: 12px;
  font-weight: 700;
}

.call-pulse {
  width: 38px;
  height: 38px;
  min-width: 38px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: #ecfeff;
  color: #0891b2;
}

.call-panel.incoming .call-pulse,
.call-panel.outgoing .call-pulse {
  animation: callPulse 1.2s ease-in-out infinite;
}

.call-controls {
  display: flex;
  gap: 8px;
}

.call-control {
  width: 38px;
  height: 38px;
  display: grid;
  place-items: center;
  border-radius: 50%;
  color: #ffffff;
  cursor: pointer;
}

.call-control.accept {
  background: #16a34a;
}

.call-control.end {
  background: #dc2626;
}

.call-control.mute {
  background: #334155;
}

.call-control.camera {
  background: #334155;
}

.call-control.camera.muted {
  background: #b45309;
}

.call-control.mute.muted {
  background: #f59e0b;
}

.remote-call-audio {
  position: fixed;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
}

@keyframes callPulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(8, 145, 178, 0.28);
  }
  50% {
    box-shadow: 0 0 0 9px rgba(8, 145, 178, 0);
  }
}

.app-rail {
  background: linear-gradient(180deg, #0891b2 0%, #0e7490 100%);
  color: #ffffff;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 14px 10px;
}

.rail-logo {
  width: 44px;
  height: 44px;
  display: grid;
  place-items: center;
}

.rail-logo :deep(.brand-logo) {
  box-shadow: none;
}

.rail-logo :deep(.brand-logo__crop) {
  border-radius: 7px;
}

.rail-actions,
.rail-bottom {
  display: grid;
  gap: 10px;
}

.rail-actions {
  margin-top: 32px;
}

.rail-bottom {
  margin-top: auto;
}

.rail-button,
.icon-button,
.tool-button,
.send-button,
.download-button {
  display: inline-grid;
  place-items: center;
  cursor: pointer;
  transition: background-color 0.18s ease, color 0.18s ease, transform 0.18s ease;
}

.rail-button {
  width: 46px;
  height: 46px;
  border-radius: 8px;
  background: transparent;
  color: #ffffff;
}

.rail-dropdown {
  display: grid;
}

.language-rail-button {
  position: relative;
}

.language-rail-button span {
  position: absolute;
  right: 7px;
  bottom: 6px;
  min-width: 15px;
  height: 13px;
  display: grid;
  place-items: center;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.18);
  color: #ffffff;
  font-size: 9px;
  font-weight: 900;
  line-height: 1;
}

.rail-button:hover,
.rail-button.active {
  background: rgba(255, 255, 255, 0.18);
  transform: translateY(-1px);
}

.profile-rail-button {
  background: rgba(255, 255, 255, 0.14);
}

.conversation-panel,
.info-panel,
.chat-header,
.composer {
  background: #ffffff;
}

.conversation-panel {
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  border-right: 1px solid #dce3ee;
}

.panel-header {
  height: 88px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 18px 12px;
  flex: 0 0 auto;
}

.eyebrow {
  margin: 0 0 2px;
  color: var(--brand);
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0;
}

.panel-header h1,
.chat-title h2,
.empty-chat h2,
.profile-block h3,
.section-title h4 {
  margin: 0;
}

.panel-header h1 {
  font-size: 24px;
  line-height: 1.2;
}

.panel-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.icon-button {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: #f0f4fa;
  color: #243044;
}

.icon-button.primary {
  background: var(--brand);
  color: #ffffff;
}

.icon-button:disabled {
  cursor: default;
  opacity: 0.45;
}

.icon-button:hover,
.tool-button:hover {
  background: var(--brand-soft);
  color: var(--brand-dark);
}

.icon-button:disabled:hover {
  background: #f0f4fa;
  color: #243044;
}

.search-box,
.quick-start,
.chip-input {
  display: flex;
  align-items: center;
  gap: 8px;
  border-radius: 8px;
  background: #f2f5f9;
  border: 1px solid transparent;
}

.search-box {
  margin: 0 18px 10px;
  padding: 0 12px;
  height: 42px;
  color: #6b778c;
  flex: 0 0 auto;
}

.search-box input,
.quick-start input,
.chip-input input,
.dialog-form input,
.dialog-form select {
  min-width: 0;
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: #172033;
}

.search-clear-button {
  width: 24px;
  height: 24px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: transparent;
  color: #64748b;
  cursor: pointer;
  flex: 0 0 auto;
}

.search-clear-button:hover {
  background: #dbeafe;
  color: var(--brand-dark);
}

.search-scope-tabs {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 18px 10px;
  border-bottom: 1px solid #edf1f6;
  overflow-x: auto;
  flex: 0 0 auto;
}

.search-scope-tabs button {
  height: 30px;
  padding: 0 3px;
  border-bottom: 2px solid transparent;
  background: transparent;
  color: #516173;
  cursor: pointer;
  font-size: 13px;
  font-weight: 850;
  white-space: nowrap;
}

.search-scope-tabs button.active {
  border-color: var(--brand);
  color: var(--brand-dark);
}

.quick-start {
  margin: 0 18px 12px;
  height: 42px;
  padding-left: 12px;
  flex: 0 0 auto;
}

.quick-start button,
.chip-input button {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand);
  color: #ffffff;
  cursor: pointer;
  flex: 0 0 auto;
}

.conversation-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding: 4px 8px 12px;
}

.search-results {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  padding: 4px 8px 12px;
}

.contact-menu {
  display: grid;
  gap: 6px;
  padding: 6px 8px 12px;
}

.contact-menu-item {
  min-height: 52px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 14px;
  border-radius: 8px;
  background: transparent;
  color: #26354b;
  cursor: pointer;
  text-align: left;
  font-weight: 800;
}

.contact-menu-item svg {
  color: var(--brand-dark);
  flex: 0 0 auto;
}

.contact-menu-item:hover,
.contact-menu-item.active {
  background: var(--brand-soft);
  color: #102033;
}

.result-section {
  display: grid;
  gap: 4px;
  margin-bottom: 14px;
}

.result-title {
  padding: 8px 10px 4px;
  color: #687789;
  font-size: 12px;
  font-weight: 800;
  text-transform: uppercase;
}

.view-all-search {
  width: calc(100% - 20px);
  min-height: 34px;
  margin: 2px 10px 8px;
  border-radius: 8px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  cursor: pointer;
  font-size: 13px;
  font-weight: 850;
}

.view-all-search:hover {
  background: #d7fbff;
}

.conversation-item {
  width: 100%;
  min-height: 68px;
  display: flex;
  gap: 12px;
  align-items: center;
  padding: 10px;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
  transition: background-color 0.18s ease, box-shadow 0.18s ease, transform 0.18s ease;
}

.conversation-item:hover {
  background: var(--brand-softest);
  box-shadow: 0 8px 20px rgba(8, 145, 178, 0.08);
  transform: translateX(2px);
}

.conversation-item.active {
  background: var(--brand-soft);
  box-shadow: inset 3px 0 0 var(--brand);
}

.conversation-item.has-unread .conversation-name {
  color: #0f172a;
  font-weight: 800;
}

.conversation-item.has-unread .conversation-main p {
  color: #1e293b;
  font-weight: 700;
}

.conversation-avatar {
  flex: 0 0 auto;
}

.avatar-presence-wrap {
  position: relative;
  flex: 0 0 auto;
  display: inline-grid;
  place-items: center;
}

.presence-dot {
  position: absolute;
  right: -1px;
  bottom: -1px;
  width: 13px;
  height: 13px;
  border-radius: 999px;
  background: #94a3b8;
  border: 2px solid #ffffff;
  box-shadow: 0 0 0 1px rgba(15, 23, 42, 0.08);
}

.presence-dot.online {
  background: #22c55e;
}

.presence-dot.small {
  width: 11px;
  height: 11px;
  border-width: 2px;
}

.presence-dot.mini {
  width: 9px;
  height: 9px;
  border-width: 1.5px;
}

.presence-dot.large {
  width: 16px;
  height: 16px;
  right: 4px;
  bottom: 4px;
}

.presence-text {
  color: #94a3b8;
  font-size: 11px;
  font-weight: 800;
  line-height: 1.2;
}

.presence-text.online {
  color: #16a34a;
}

.conversation-avatar.group {
  width: 44px;
  height: 44px;
  position: relative;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: linear-gradient(135deg, var(--brand-focus), var(--brand));
  color: #ffffff;
  box-shadow: inset 0 0 0 2px rgba(255, 255, 255, 0.28);
}

.conversation-avatar.group span {
  position: absolute;
  right: -3px;
  bottom: -3px;
  min-width: 18px;
  height: 18px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: #ffffff;
  border: 1px solid var(--brand-border);
  color: var(--brand-dark);
  font-size: 11px;
  font-weight: 800;
}

.conversation-main {
  min-width: 0;
  flex: 1;
}

.conversation-top {
  display: flex;
  gap: 8px;
  justify-content: space-between;
  align-items: baseline;
}

.conversation-meta {
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: 6px;
}

.unread-badge {
  min-width: 20px;
  height: 20px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: #ff3b30;
  color: #ffffff;
  font-size: 11px;
  font-weight: 800;
  padding: 0 6px;
}

.conversation-name {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 700;
}

.conversation-top time {
  flex: 0 0 auto;
  color: #8a95a7;
  font-size: 12px;
}

.conversation-main p {
  margin: 3px 0 0;
  color: #6b778c;
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-result {
  min-height: 62px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border-radius: 8px;
  background: transparent;
  transition: background-color 0.18s ease, box-shadow 0.18s ease, transform 0.18s ease;
}

.user-result:hover {
  background: var(--brand-softest);
  box-shadow: 0 8px 20px rgba(8, 145, 178, 0.08);
  transform: translateX(2px);
}

.user-result-main {
  min-width: 0;
  flex: 1;
  display: grid;
  gap: 2px;
}

.user-result-main strong,
.user-result-main span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-result-main span {
  color: #6b778c;
  font-size: 13px;
}

.result-action {
  flex: 0 0 auto;
  height: 32px;
  border-radius: 8px;
  padding: 0 10px;
  background: var(--brand);
  color: #ffffff;
  cursor: pointer;
  font-weight: 800;
}

.result-action.ghost {
  background: var(--brand-soft);
  color: var(--brand-dark);
}

.conversation-name svg {
  flex: 0 0 auto;
  color: var(--brand-dark);
}

.search-hit {
  width: 100%;
  min-height: 58px;
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 9px 10px;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
  text-align: left;
}

.search-hit:hover {
  background: var(--brand-softest);
}

.search-hit-icon {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  flex: 0 0 auto;
}

.search-hit-icon.pdf {
  background: #fee2e2;
  color: #b91c1c;
}

.search-hit-icon.excel {
  background: #dcfce7;
  color: #15803d;
}

.search-hit-icon.word,
.search-hit-icon.file {
  background: #dbeafe;
  color: #1d4ed8;
}

.search-hit-icon.folder,
.search-hit-icon.archive {
  background: #fef3c7;
  color: #b45309;
}

.search-hit-main {
  min-width: 0;
  display: grid;
  gap: 2px;
}

.search-hit-main strong,
.search-hit-main span,
.search-hit-main p {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.search-hit-main strong {
  color: #172033;
  font-size: 14px;
  font-weight: 850;
}

.search-hit-main span,
.search-hit-main p {
  color: #7b8798;
  font-size: 12px;
}

.list-state,
.empty-list,
.message-state,
.empty-chat {
  color: #7b8798;
}

.list-state,
.empty-list {
  padding: 28px 18px;
  text-align: center;
}

.list-state.compact {
  padding: 10px 0;
}

.empty-list {
  display: grid;
  justify-items: center;
  gap: 8px;
}

.directory-pane {
  min-width: 0;
  min-height: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
  background: #ffffff;
}

.directory-header {
  height: 72px;
  display: flex;
  align-items: center;
  padding: 0 24px;
  border-bottom: 1px solid #dce3ee;
  flex: 0 0 auto;
}

.directory-title {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 12px;
  color: #172033;
}

.directory-title svg {
  color: var(--brand-dark);
  flex: 0 0 auto;
}

.directory-title h2 {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 18px;
  line-height: 1.3;
}

.directory-content {
  min-height: 0;
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 22px 28px;
  overflow: hidden;
}

.directory-section-title {
  color: #334155;
  font-size: 14px;
  font-weight: 900;
}

.directory-tabs {
  display: none;
}

.directory-search {
  height: 42px;
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 0 12px;
  border-radius: 8px;
  background: #f2f5f9;
  border: 1px solid transparent;
  color: #6b778c;
}

.directory-search input {
  min-width: 0;
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: #172033;
}

.directory-search:focus-within {
  border-color: var(--brand-focus);
  box-shadow: 0 0 0 3px var(--brand-tint);
}

.directory-list {
  min-height: 0;
  flex: 1 1 auto;
  overflow-y: auto;
  padding-right: 4px;
}

.directory-letter-group {
  display: grid;
  gap: 4px;
  padding-bottom: 18px;
}

.directory-letter-group h3 {
  margin: 0;
  padding: 0 0 6px 14px;
  color: #475569;
  font-size: 15px;
  font-weight: 900;
  line-height: 1.2;
}

.directory-item {
  width: 100%;
  min-height: 64px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 14px;
  border-radius: 8px;
  background: transparent;
  color: #172033;
  cursor: pointer;
  text-align: left;
  transition: background-color 0.18s ease, box-shadow 0.18s ease, transform 0.18s ease;
}

.directory-item:hover {
  background: var(--brand-softest);
  box-shadow: 0 10px 22px rgba(8, 145, 178, 0.1);
  transform: translateX(2px);
}

.directory-item > span {
  min-width: 0;
  display: grid;
  gap: 2px;
}

.directory-item strong,
.directory-item small {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.directory-item strong {
  font-size: 15px;
  font-weight: 850;
}

.directory-item small {
  color: #7b8798;
  font-size: 12px;
}

.directory-group-avatar {
  width: 42px;
  height: 42px;
  position: relative;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: linear-gradient(135deg, var(--brand-focus), var(--brand));
  color: #ffffff;
}

.directory-group-avatar em {
  position: absolute;
  right: -4px;
  bottom: -4px;
  min-width: 18px;
  height: 18px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: #ffffff;
  border: 1px solid var(--brand-border);
  color: var(--brand-dark);
  font-size: 10px;
  font-style: normal;
  font-weight: 900;
}

.chat-pane {
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: #f4f7fb;
  overflow: hidden;
}

.chat-shell:not(.has-active) .chat-pane {
  grid-column: 3 / -1;
}

.chat-header {
  height: 72px;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 0 18px;
  border-bottom: 1px solid #dce3ee;
  flex: 0 0 auto;
}

.mobile-back {
  display: none;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: #f0f4fa;
  color: #243044;
}

.chat-title {
  min-width: 0;
  flex: 1;
}

.chat-title h2 {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 18px;
  line-height: 1.3;
}

.chat-title span,
.profile-block span,
.member-item span,
.attachment-meta span,
.muted {
  color: #7b8798;
  font-size: 13px;
}

.conversation-search {
  min-width: 210px;
  width: min(320px, 32vw);
  height: 38px;
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 8px 0 10px;
  border-radius: 8px;
  background: #f2f5f9;
  border: 1px solid transparent;
  color: #64748b;
}

.conversation-search:focus-within {
  border-color: var(--brand-focus);
  box-shadow: 0 0 0 3px var(--brand-tint);
}

.conversation-search input {
  min-width: 0;
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: #172033;
}

.conversation-search button {
  width: 24px;
  height: 24px;
  display: grid;
  place-items: center;
  border-radius: 6px;
  background: transparent;
  color: #64748b;
  cursor: pointer;
  flex: 0 0 auto;
}

.conversation-search button:hover:not(:disabled) {
  background: #e0f2fe;
  color: var(--brand-dark);
}

.conversation-search button:disabled {
  cursor: default;
  opacity: 0.45;
}

.conversation-search-count {
  color: #64748b;
  font-size: 12px;
  font-weight: 850;
  white-space: nowrap;
}

.chat-actions {
  display: flex;
  gap: 8px;
}

.pinned-message-bar {
  min-height: 44px;
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto 32px;
  align-items: center;
  gap: 8px;
  padding: 6px 18px;
  border-bottom: 1px solid #dce3ee;
  background: #ffffff;
  flex: 0 0 auto;
}

.pinned-message-count {
  min-width: 42px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 2px;
  padding: 0 8px;
  border-radius: 8px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  cursor: pointer;
  font-weight: 900;
}

.pinned-message-list {
  display: grid;
  gap: 6px;
}

.pinned-message-list > strong {
  padding: 2px 4px 6px;
  color: #172033;
}

.pinned-message-list > button {
  min-width: 0;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  padding: 9px;
  border-radius: 8px;
  background: #f6f8fb;
  color: #475569;
  cursor: pointer;
  text-align: left;
}

.pinned-message-list > button span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pinned-message-main {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 9px;
  border-radius: 8px;
  padding: 6px 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  cursor: pointer;
  text-align: left;
}

.pinned-message-main > span {
  min-width: 0;
  display: grid;
  gap: 1px;
}

.pinned-message-main strong,
.pinned-message-main em {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pinned-message-main strong {
  font-size: 12px;
  line-height: 1.2;
}

.pinned-message-main em {
  color: #64748b;
  font-size: 12px;
  font-style: normal;
}

.pinned-message-remove {
  width: 32px;
  height: 32px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #f0f4fa;
  color: #64748b;
  cursor: pointer;
}

.pinned-message-remove:hover {
  background: #e2e8f0;
  color: #243044;
}

.typing-indicator {
  min-height: 30px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 5px 20px;
  border-top: 1px solid #e7edf4;
  background: rgba(255, 255, 255, 0.86);
  color: #64748b;
  font-size: 12px;
  font-weight: 700;
  flex: 0 0 auto;
}

.typing-indicator > span {
  display: inline-flex;
  align-items: center;
  gap: 2px;
}

.typing-indicator i {
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: var(--brand);
  animation: typingPulse 1s ease-in-out infinite;
}

.typing-indicator i:nth-child(2) {
  animation-delay: 0.15s;
}

.typing-indicator i:nth-child(3) {
  animation-delay: 0.3s;
}

.message-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 20px 28px;
  background-position: center;
  background-size: cover;
}

.message-list-wrap {
  position: relative;
  min-height: 0;
  display: flex;
  flex: 1 1 auto;
}

.message-list-wrap .message-list {
  flex: 1 1 auto;
}

.latest-message-button {
  position: absolute;
  right: 22px;
  bottom: 18px;
  z-index: 5;
  width: 42px;
  height: 42px;
  display: grid;
  place-items: center;
  border: 1px solid rgba(8, 145, 178, 0.22);
  border-radius: 999px;
  background: #ffffff;
  color: var(--brand-dark);
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.2);
  cursor: pointer;
}

.latest-message-button:hover {
  background: var(--brand-softest);
}

.latest-message-badge {
  position: absolute;
  top: -7px;
  right: -7px;
  min-width: 20px;
  height: 20px;
  display: grid;
  place-items: center;
  padding: 0 5px;
  border: 2px solid #ffffff;
  border-radius: 999px;
  background: #ef4444;
  color: #ffffff;
  font-size: 10px;
  font-weight: 900;
  line-height: 1;
}

.message-history-loader {
  width: fit-content;
  margin: 0 auto 12px;
  padding: 6px 10px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.82);
  color: #64748b;
  font-size: 12px;
  font-weight: 800;
  box-shadow: 0 1px 4px rgba(15, 23, 42, 0.08);
}

.message-state,
.empty-chat {
  height: 100%;
  display: grid;
  align-content: center;
  justify-items: center;
  gap: 10px;
  text-align: center;
}

.empty-chat > svg,
.empty-chat > h2,
.empty-chat > p {
  display: none;
}

.welcome-copy {
  display: grid;
  justify-items: center;
  gap: 10px;
  max-width: 420px;
}

.welcome-copy :deep(.brand-logo) {
  margin-bottom: 4px;
}

.welcome-copy h2 {
  margin: 0;
  color: #18243a;
  font-size: 24px;
  line-height: 1.25;
}

.welcome-copy p {
  margin: 0;
  color: #7b8798;
  font-size: 15px;
}

.empty-chat p {
  margin: 0;
}

.message-row {
  display: flex;
  gap: 8px;
  margin: 0 0 12px;
  align-items: flex-end;
  content-visibility: auto;
  contain-intrinsic-size: 86px;
  animation: messageEnter 0.22s ease both;
}

.message-row.highlight .message-bubble {
  box-shadow: 0 0 0 3px var(--brand-tint), 0 1px 1px rgba(15, 23, 42, 0.04);
}

.message-row.search-match .message-bubble {
  box-shadow: 0 0 0 2px rgba(251, 191, 36, 0.48), 0 1px 1px rgba(15, 23, 42, 0.04);
}

.message-row.current-search-match .message-bubble {
  box-shadow: 0 0 0 3px var(--brand-focus), 0 12px 26px rgba(8, 145, 178, 0.16);
}

.message-row.pinned-message .message-bubble {
  box-shadow: 0 0 0 2px var(--brand-focus), 0 10px 24px rgba(8, 145, 178, 0.14);
}

.message-row.send-failed .message-bubble {
  border-color: #fda4af;
}

.message-row.own {
  justify-content: flex-end;
}

.message-row.system-message,
.message-row.poll-message {
  justify-content: center;
}

.message-stack {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  max-width: min(620px, 74%);
}

.message-row.own .message-stack {
  align-items: flex-end;
}

.message-row.system-message .message-stack,
.message-row.poll-message .message-stack {
  width: min(460px, 92%);
  max-width: min(460px, 92%);
  align-items: center;
}

.message-content-row {
  max-width: 100%;
  display: flex;
  align-items: flex-end;
  gap: 6px;
}

.message-row.own .message-content-row {
  flex-direction: row-reverse;
}

.message-row.system-message .message-content-row,
.message-row.poll-message .message-content-row {
  justify-content: center;
}

.sender-name {
  margin: 0 0 4px 2px;
  padding: 0;
  border: 0;
  background: transparent;
  color: #637083;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}

.sender-name:hover {
  color: var(--brand-dark);
}

.message-profile-trigger {
  padding: 0;
  border: 0;
  background: transparent;
  cursor: pointer;
}

.message-bubble {
  position: relative;
  min-width: 84px;
  max-width: 100%;
  padding: 9px 10px 7px;
  border-radius: 8px;
  background: #ffffff;
  border: 1px solid #e2e8f0;
  box-shadow: 0 1px 1px rgba(15, 23, 42, 0.04);
  overflow-wrap: anywhere;
  transition: box-shadow 0.18s ease, transform 0.18s ease;
}

.message-bubble.has-reactions {
  margin-bottom: 10px;
}

.message-stack:hover .message-bubble {
  box-shadow: 0 10px 24px rgba(15, 23, 42, 0.1);
  transform: translateY(-1px);
}

.message-row.own .message-bubble {
  background: var(--brand-soft);
  border-color: var(--brand-border);
}

.message-bubble.call {
  min-width: 224px;
  padding: 8px 10px;
  background: #f8fafc;
  border-color: #cbd5e1;
}

.message-row.own .message-bubble.call {
  background: #ecfeff;
  border-color: #a5f3fc;
}

.call-message-card {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.call-message-icon {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  border-radius: 50%;
  background: #dcfce7;
  color: #15803d;
}

.call-message-card.outgoing .call-message-icon {
  background: #cffafe;
  color: #0e7490;
}

.call-message-card.missed .call-message-icon {
  background: #fee2e2;
  color: #dc2626;
}

.call-message-copy {
  min-width: 0;
  display: grid;
  gap: 2px;
}

.call-message-copy strong,
.call-message-copy small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.call-message-copy strong {
  color: #172033;
  font-size: 13px;
  line-height: 1.25;
}

.call-message-copy small {
  color: #64748b;
  font-size: 11px;
  font-weight: 700;
}

.message-row.poll-message .message-bubble,
.message-row.system-message .message-bubble {
  background: #ffffff;
  border-color: #dce5f1;
}

.message-row.system-message .message-bubble {
  min-width: 0;
  max-width: 100%;
  padding: 0;
  border: 0;
  background: transparent;
  box-shadow: none;
}

.message-row.system-message:hover .message-bubble {
  box-shadow: none;
  transform: none;
}

.system-notice {
  display: inline-flex;
  max-width: 100%;
  padding: 6px 12px;
  border-radius: 999px;
  background: #eef4f8;
  color: #64748b;
  font-size: 12px;
  font-weight: 750;
  line-height: 1.35;
  text-align: center;
  overflow-wrap: anywhere;
}

.message-tombstone {
  color: #7b8798;
  font-size: 13px;
  font-style: italic;
}

.reply-reference {
  width: 100%;
  display: grid;
  gap: 2px;
  margin-bottom: 7px;
  padding: 7px 8px;
  border-left: 3px solid var(--brand);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.72);
  color: #243044;
  cursor: pointer;
  text-align: left;
}

.reply-reference strong,
.reply-compose strong {
  font-size: 12px;
  color: var(--brand-dark);
}

.reply-reference span,
.reply-compose span,
.forward-preview span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #637083;
  font-size: 12px;
}

.forwarded-label {
  display: flex;
  align-items: center;
  gap: 4px;
  margin-bottom: 6px;
  color: #64748b;
  font-size: 12px;
  font-weight: 700;
}

.message-actions {
  display: flex;
  gap: 4px;
  margin-bottom: 2px;
  opacity: 0;
  pointer-events: none;
  transform: translateY(2px);
  transition: opacity 0.15s ease, transform 0.15s ease;
  flex: 0 0 auto;
}

.message-row:hover .message-actions,
.message-row:focus-within .message-actions {
  opacity: 1;
  pointer-events: auto;
  transform: translateY(0);
}

.message-actions :deep(.el-dropdown) {
  display: grid;
}

.message-actions .message-action-button {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #ffffff;
  color: #64748b;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.08);
  cursor: pointer;
}

.message-actions .message-action-button:hover {
  color: var(--brand-dark);
  background: var(--brand-softest);
}

.message-delivery-status {
  min-height: 18px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding-top: 3px;
  color: #7b8798;
  font-size: 11px;
}

.message-delivery-status.read {
  color: var(--brand-dark);
}

.message-delivery-status.failed {
  color: #e11d48;
}

.message-delivery-status .message-retry-button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  border-radius: 7px;
  padding: 3px 6px;
  background: #fff1f2;
  color: #be123c;
  cursor: pointer;
  font-size: 11px;
  font-weight: 800;
}

.message-readers-button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  font: inherit;
}

.message-reactions {
  position: absolute;
  right: 7px;
  bottom: -11px;
  z-index: 2;
  display: flex;
  flex-wrap: nowrap;
  gap: 2px;
  max-width: calc(100% - 14px);
}

.message-reactions button {
  min-height: 20px;
  height: 20px;
  display: inline-flex;
  align-items: center;
  gap: 2px;
  border: 1px solid #dce5f1;
  border-radius: 999px;
  padding: 0 5px;
  background: rgba(255, 255, 255, 0.96);
  color: #475569;
  cursor: pointer;
  box-shadow: 0 1px 3px rgba(15, 23, 42, 0.12);
  font-size: 12px;
}

.message-reactions .reaction-summary-button {
  height: 18px;
  min-height: 18px;
  gap: 4px;
  padding: 0 5px 0 3px;
}

.reaction-summary-emojis {
  display: inline-flex;
  align-items: center;
}

.reaction-summary-emojis > span {
  width: 14px;
  height: 14px;
  display: inline-grid;
  place-items: center;
  margin-left: -3px;
  border-radius: 50%;
  background: #fff;
  font-size: 11px;
  line-height: 1;
}

.reaction-summary-emojis > span:first-child {
  margin-left: 0;
}

.message-reactions button.mine {
  border-color: var(--brand-focus);
  background: var(--brand-softest);
  color: var(--brand-dark);
}

.message-reactions button:disabled {
  cursor: wait;
  opacity: 0.65;
}

.message-reactions small {
  font-size: 10px;
  font-weight: 850;
}

.message-edited-link {
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  font: inherit;
  text-decoration: underline dotted;
  text-underline-offset: 2px;
}

:global(.reaction-detail-popper) {
  padding: 10px !important;
}

:global(.reaction-detail) {
  display: grid;
  gap: 8px;
}

:global(.reaction-overview) {
  max-height: 360px;
  overflow-y: auto;
}

:global(.reaction-detail-group) {
  display: grid;
  gap: 6px;
  padding-top: 8px;
  border-top: 1px solid #eef2f7;
}

:global(.reaction-detail-heading) {
  display: flex;
  align-items: center;
  gap: 6px;
}

:global(.reaction-detail-heading > span) {
  font-size: 17px;
}

:global(.reaction-detail-heading > b) {
  color: #475569;
  font-size: 12px;
}

:global(.reaction-detail-heading .reaction-detail-toggle) {
  margin-left: auto;
}

:global(.reaction-detail > strong) {
  color: #1e293b;
  font-size: 13px;
}

:global(.reaction-detail ul) {
  display: grid;
  gap: 6px;
  max-height: 210px;
  margin: 0;
  padding: 0;
  overflow-y: auto;
  list-style: none;
}

:global(.reaction-detail li) {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

:global(.reaction-detail li > span) {
  overflow: hidden;
  color: #334155;
  text-overflow: ellipsis;
  white-space: nowrap;
}

:global(.reaction-detail-toggle) {
  padding: 6px 8px;
  border: 0;
  border-radius: 7px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  cursor: pointer;
  font-size: 12px;
  font-weight: 750;
}

:global(.reaction-detail-toggle:disabled) {
  cursor: wait;
  opacity: 0.6;
}

:global(.message-readers-popper) {
  padding: 10px !important;
}

:global(.message-readers-detail) {
  display: grid;
  gap: 8px;
}

:global(.message-readers-detail > strong) {
  color: #1e293b;
  font-size: 13px;
}

:global(.message-readers-detail ul) {
  display: grid;
  gap: 7px;
  max-height: 280px;
  margin: 0;
  padding: 0;
  overflow-y: auto;
  list-style: none;
}

:global(.message-readers-detail li) {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

:global(.message-readers-detail li > span) {
  min-width: 0;
  display: grid;
  flex: 1;
}

:global(.message-readers-detail li b) {
  overflow: hidden;
  color: #334155;
  font-size: 12px;
  font-weight: 700;
  text-overflow: ellipsis;
  white-space: nowrap;
}

:global(.message-readers-detail li small) {
  color: #94a3b8;
  font-size: 10px;
}

.edit-history-state {
  padding: 28px 12px;
  color: #64748b;
  text-align: center;
}

.edit-history-list {
  display: grid;
  gap: 12px;
  max-height: 62vh;
  margin: 0;
  padding: 0;
  overflow-y: auto;
  list-style: none;
}

.edit-history-list > li {
  display: grid;
  gap: 8px;
  padding: 10px;
  border: 1px solid #e2e8f0;
  border-radius: 10px;
}

.edit-history-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

.edit-history-meta > span {
  min-width: 0;
  display: grid;
  flex: 1;
}

.edit-history-meta strong,
.edit-history-meta small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.edit-history-meta small,
.edit-history-meta em {
  color: #64748b;
  font-size: 11px;
  font-style: normal;
}

.edit-history-change {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: 8px;
}

.edit-history-change p {
  min-width: 0;
  margin: 0;
  padding: 8px;
  border-radius: 8px;
  background: #f8fafc;
  color: #334155;
  overflow-wrap: anywhere;
  white-space: pre-wrap;
}

.edit-history-change p:last-child {
  background: #f0fdf4;
}

.edit-history-change small {
  display: block;
  margin-bottom: 4px;
  color: #64748b;
  font-weight: 800;
}

:global(.reaction-picker-menu) {
  display: flex;
  min-width: 0;
  padding: 4px;
}

:global(.reaction-picker-menu .el-dropdown-menu__item) {
  width: 38px;
  height: 38px;
  justify-content: center;
  padding: 0;
  border-radius: 8px;
}

:global(.reaction-picker-emoji) {
  font-size: 20px;
}

.message-text {
  margin: 0;
  white-space: pre-wrap;
}

.message-text .mention {
  color: #2563eb;
  font-weight: 800;
  background: #eff6ff;
  border-radius: 6px;
  padding: 1px 3px;
}

.message-text .mention-button {
  display: inline;
  border: 0;
  cursor: pointer;
  font: inherit;
  line-height: inherit;
}

.message-text .mention-button:hover {
  background: #dbeafe;
  text-decoration: underline;
}

.message-link {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--brand-dark);
  word-break: break-all;
}

.poll-card {
  width: min(420px, 82vw);
  display: grid;
  gap: 10px;
}

.poll-card-header {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  color: #172033;
}

.poll-card-header svg {
  flex: 0 0 auto;
  margin-top: 1px;
  color: var(--brand-dark);
}

.poll-card-header strong {
  min-width: 0;
  font-size: 14px;
  line-height: 1.35;
  overflow-wrap: anywhere;
}

.poll-card-header span {
  min-width: 0;
  display: grid;
  gap: 4px;
}

.poll-card-header em {
  width: fit-content;
  border-radius: 999px;
  padding: 2px 8px;
  background: #edf2f7;
  color: #64748b;
  font-size: 11px;
  font-style: normal;
  font-weight: 850;
}

.poll-options {
  display: grid;
  gap: 7px;
}

.poll-option {
  position: relative;
  min-height: 42px;
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 8px 10px;
  border: 1px solid #dce5f1;
  border-radius: 8px;
  background: #ffffff;
  overflow: hidden;
  cursor: pointer;
}

.poll-option.selected {
  border-color: var(--brand);
  background: var(--brand-softest);
}

.poll-option.disabled {
  cursor: not-allowed;
  opacity: 0.72;
}

.poll-option input {
  position: relative;
  z-index: 1;
  flex: 0 0 auto;
  accent-color: var(--brand);
}

.poll-option-main {
  position: relative;
  z-index: 1;
  min-width: 0;
  display: grid;
  gap: 2px;
  flex: 1;
}

.poll-option-text {
  min-width: 0;
  color: #1f2d42;
  font-size: 13px;
  font-weight: 700;
  overflow-wrap: anywhere;
}

.poll-voters {
  color: #64748b;
  font-size: 11px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.poll-option-count {
  position: relative;
  z-index: 1;
  color: #526173;
  font-size: 12px;
  font-weight: 800;
}

.poll-option-bar {
  position: absolute;
  inset: 0 auto 0 0;
  width: 0;
  background: rgba(42, 157, 143, 0.14);
  transition: width 0.2s ease;
}

.poll-custom-form {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 34px;
  gap: 6px;
}

.poll-custom-form input {
  min-width: 0;
  height: 34px;
  border: 1px solid #dce5f1;
  border-radius: 8px;
  padding: 0 10px;
  background: #ffffff;
  color: #1f2d42;
}

.poll-custom-form button {
  width: 34px;
  height: 34px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand);
  color: #ffffff;
  cursor: pointer;
}

.poll-custom-form button:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.poll-meta {
  color: #64748b;
  font-size: 11px;
}

.poll-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.poll-footer-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.poll-close-button,
.poll-pin-button {
  min-height: 30px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  border-radius: 8px;
  padding: 0 10px;
  background: #fff1f2;
  color: #be123c;
  cursor: pointer;
  font-size: 12px;
  font-weight: 850;
}

.poll-pin-button {
  background: var(--brand-softest);
  color: var(--brand-dark);
}

.poll-close-button:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}

.message-bubble time {
  display: block;
  margin-top: 4px;
  color: #7b8798;
  font-size: 11px;
  text-align: right;
}

.image-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 168px));
  gap: 6px;
  margin-top: 4px;
}

.image-grid.compact {
  grid-template-columns: repeat(2, minmax(0, 118px));
}

.video-grid {
  display: grid;
  gap: 8px;
  margin-top: 6px;
}

.image-card {
  position: relative;
  border-radius: 8px;
  overflow: hidden;
  background: #dce3ee;
  border: 1px solid rgba(0, 0, 0, 0.05);
}

.video-card {
  position: relative;
  overflow: hidden;
  width: min(360px, 64vw);
  border-radius: 8px;
  background: #0f172a;
  border: 1px solid rgba(0, 0, 0, 0.08);
}

.video-card video {
  width: 100%;
  max-height: 260px;
  display: block;
  background: #0f172a;
}

.image-preview {
  display: block;
}

.image-preview img {
  width: 100%;
  height: 150px;
  display: block;
  object-fit: cover;
}

.image-grid.compact .image-preview img {
  height: 108px;
}

.image-download-button,
.shared-media-download {
  position: absolute;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: rgba(15, 23, 42, 0.74);
  color: #ffffff;
  box-shadow: 0 8px 18px rgba(15, 23, 42, 0.18);
  opacity: 0.92;
  transform: translateY(0);
  transition: opacity 0.18s ease, transform 0.18s ease, background-color 0.18s ease;
}

.image-download-button {
  top: 7px;
  right: 7px;
  width: 32px;
  height: 32px;
}

.image-card:hover .image-download-button,
.video-card:hover .image-download-button,
.image-download-button:focus-visible,
.shared-media-item:hover .shared-media-download,
.shared-media-download:focus-visible {
  opacity: 1;
}

.image-download-button:hover,
.shared-media-download:hover {
  background: var(--brand-dark);
}

.voice-list {
  display: grid;
  gap: 8px;
  margin-top: 6px;
}

.voice-player {
  min-width: min(360px, 58vw);
  display: grid;
  grid-template-columns: 36px minmax(0, 1fr) 30px;
  gap: 8px;
  align-items: center;
  padding: 8px;
  border-radius: 8px;
  background: rgba(240, 237, 255, 0.7);
  border: 1px solid #d9d0ff;
}

.voice-icon {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #f0edff;
  color: #6d4aff;
}

.voice-player audio {
  width: 100%;
  min-width: 0;
  height: 34px;
}

.attachment-list {
  display: grid;
  gap: 8px;
  margin-top: 6px;
}

.attachment-item {
  min-width: min(390px, 58vw);
  display: grid;
  grid-template-columns: 38px minmax(0, 1fr) 30px;
  gap: 8px;
  align-items: center;
  padding: 8px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.74);
  border: 1px solid #dce7f7;
}

.attachment-icon {
  width: 38px;
  height: 38px;
  position: relative;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand);
}

.attachment-badge,
.shared-file-icon small {
  position: absolute;
  right: -5px;
  bottom: -5px;
  min-width: 23px;
  height: 14px;
  display: grid;
  place-items: center;
  border-radius: 4px;
  background: #ffffff;
  border: 1px solid currentColor;
  color: inherit;
  font-size: 8px;
  font-weight: 900;
  line-height: 1;
  padding: 0 3px;
}

.attachment-item.word .attachment-icon {
  background: var(--brand-softest);
  color: var(--brand);
}

.attachment-item.excel .attachment-icon {
  background: #e7f7ed;
  color: #16803d;
}

.attachment-item.ppt .attachment-icon {
  background: #fff0e8;
  color: #d45a16;
}

.attachment-item.pdf .attachment-icon {
  background: #ffecec;
  color: #dc2626;
}

.attachment-item.archive .attachment-icon,
.attachment-item.folder .attachment-icon {
  background: #fff7dd;
  color: #b77900;
}

.attachment-item.audio .attachment-icon,
.attachment-item.voice .attachment-icon,
.attachment-item.video .attachment-icon,
.attachment-item.code .attachment-icon {
  background: #f0edff;
  color: #6d4aff;
}

.attachment-meta {
  min-width: 0;
  display: grid;
  gap: 1px;
}

.attachment-meta a,
.shared-files a {
  color: #172033;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.download-button {
  width: 30px;
  height: 30px;
  border-radius: 8px;
  color: var(--brand-dark);
}

.composer {
  border-top: 1px solid #dce3ee;
  padding: 10px 14px 12px;
  flex: 0 0 auto;
}

.reply-compose,
.forward-preview {
  min-width: 0;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
  padding: 8px 10px;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
}

.reply-compose > div {
  min-width: 0;
  display: grid;
}

.reply-compose button {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.forward-preview {
  grid-template-columns: auto minmax(0, 1fr);
}

.forward-conversation-list {
  display: grid;
  gap: 8px;
  max-height: 360px;
  overflow-y: auto;
}

.forward-conversation {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  padding: 8px;
  border-radius: 8px;
  background: #f5f7fb;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.forward-conversation.selected {
  background: var(--brand-soft);
  box-shadow: inset 0 0 0 1px var(--brand-focus);
}

.forward-conversation span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-files {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 8px;
}

.pending-file,
.chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  max-width: 300px;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  padding: 6px 8px;
  font-size: 13px;
}

.pending-file span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pending-file small {
  flex: 0 0 auto;
  color: #5d7190;
}

.pending-file button,
.chip button,
.section-title button {
  display: grid;
  place-items: center;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.voice-recording {
  height: 40px;
  display: grid;
  grid-template-columns: auto auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 9px;
  padding: 0 10px;
  margin-bottom: 8px;
  border-radius: 8px;
  background: #fff1f2;
  border: 1px solid #fecdd3;
  color: #b91c1c;
}

.voice-recording span:last-of-type {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #7f1d1d;
}

.voice-recording button {
  width: 30px;
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.record-dot {
  width: 9px;
  height: 9px;
  border-radius: 999px;
  background: #ef4444;
  box-shadow: 0 0 0 4px rgba(239, 68, 68, 0.14);
}

.composer-body {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 8px;
  align-items: end;
}

.composer-input-wrap {
  position: relative;
  min-width: 0;
}

.mention-menu {
  position: absolute;
  left: 0;
  right: 0;
  bottom: calc(100% + 8px);
  z-index: 30;
  max-height: 240px;
  overflow-y: auto;
  display: grid;
  gap: 2px;
  padding: 6px;
  border-radius: 8px;
  border: 1px solid #d8e4f4;
  background: #ffffff;
  box-shadow: 0 16px 42px rgba(15, 23, 42, 0.18);
}

.mention-menu button {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 8px;
  border-radius: 8px;
  padding: 7px;
  background: transparent;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.mention-menu button:hover,
.mention-menu button.selected {
  background: var(--brand-softest);
}

.mention-menu span {
  min-width: 0;
  display: grid;
}

.mention-menu .mention-all-icon {
  width: 28px;
  height: 28px;
  min-width: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  background: var(--brand-softest);
  color: var(--brand);
}

.mention-menu strong,
.mention-menu small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mention-menu small {
  color: #64748b;
}

.composer-tools {
  display: flex;
  gap: 4px;
  padding-bottom: 1px;
}

.tool-button {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  background: transparent;
  color: #596779;
}

.tool-button.active {
  background: var(--brand-soft);
  color: var(--brand);
}

.tool-button.recording {
  background: #fee2e2;
  color: #dc2626;
}

.tool-button:disabled {
  cursor: not-allowed;
  opacity: 0.52;
}

textarea {
  width: 100%;
  min-height: 38px;
  max-height: 120px;
  resize: none;
  border: 1px solid #dce3ee;
  border-radius: 8px;
  outline: 0;
  padding: 8px 11px;
  color: #172033;
  line-height: 1.4;
}

textarea:focus,
.search-box:focus-within,
.quick-start:focus-within,
.chip-input:focus-within,
.dialog-form input:focus {
  border-color: var(--brand-focus);
  box-shadow: 0 0 0 3px var(--brand-tint);
}

.send-button {
  width: 40px;
  height: 38px;
  border-radius: 8px;
  background: var(--brand);
  color: #ffffff;
  box-shadow: 0 10px 20px rgba(8, 145, 178, 0.18);
}

.send-button:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.info-panel {
  min-width: 0;
  min-height: 0;
  overflow-y: auto;
  border-left: 1px solid #dce3ee;
  padding: 20px 16px;
}

.info-backdrop,
.info-panel-close {
  display: none;
}

.storage-view {
  min-height: 100%;
  display: flex;
  flex-direction: column;
  margin: -20px -16px;
  background: #ffffff;
}

.storage-header {
  min-height: 64px;
  display: grid;
  grid-template-columns: 40px minmax(0, 1fr) 40px;
  align-items: center;
  padding: 0 12px;
  border-bottom: 1px solid #dce3ee;
}

.storage-header button {
  width: 36px;
  height: 36px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: transparent;
  color: #243044;
  cursor: pointer;
}

.storage-header button:hover {
  background: #f0f4fa;
}

.storage-header h3 {
  min-width: 0;
  margin: 0;
  overflow: hidden;
  text-align: center;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: #172033;
  font-size: 17px;
}

.storage-tabs {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 4px;
  padding: 0 12px;
  border-bottom: 1px solid #edf1f6;
}

.storage-tabs button {
  min-width: 0;
  height: 44px;
  border-bottom: 2px solid transparent;
  background: transparent;
  color: #475569;
  cursor: pointer;
  font-weight: 850;
}

.storage-tabs button.active {
  border-color: var(--brand);
  color: var(--brand-dark);
}

.storage-content {
  min-height: 0;
  flex: 1 1 auto;
  padding: 14px;
}

.storage-group {
  display: grid;
  gap: 10px;
  padding-bottom: 22px;
}

.storage-group h4 {
  margin: 0;
  color: #334155;
  font-size: 14px;
  line-height: 1.2;
}

.storage-media-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}

.storage-list {
  display: grid;
  gap: 8px;
}

.storage-list-item {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px;
  border-radius: 8px;
  background: #f5f7fb;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.storage-list-item:hover {
  background: var(--brand-softest);
}

.storage-list-item > span:last-child {
  min-width: 0;
  display: grid;
  gap: 2px;
}

.storage-list-item strong,
.storage-list-item em {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.storage-list-item strong {
  font-size: 13px;
}

.storage-list-item em {
  color: #7b8798;
  font-size: 12px;
  font-style: normal;
}

.storage-empty {
  padding-top: 24px;
  text-align: center;
}

.profile-block {
  display: grid;
  justify-items: center;
  gap: 8px;
  padding-bottom: 18px;
  border-bottom: 1px solid #edf1f6;
  text-align: center;
}

.conversation-cover {
  width: 100%;
  aspect-ratio: 16 / 7;
  position: relative;
  overflow: hidden;
  border-radius: 8px;
  background: linear-gradient(135deg, var(--brand-softest), #f5f7fb);
}

.conversation-cover img {
  width: 100%;
  height: 100%;
  display: block;
  object-fit: cover;
}

.conversation-cover.empty {
  border: 1px dashed var(--brand-border);
}

.conversation-avatar-editor {
  position: relative;
}

.conversation-avatar-editor.with-cover {
  margin-top: -34px;
}

.cover-upload-button,
.avatar-upload-button.mini {
  width: 30px;
  height: 30px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.92);
  color: var(--brand-dark);
  box-shadow: 0 8px 18px rgba(15, 23, 42, 0.12);
  cursor: pointer;
}

.cover-upload-button {
  position: absolute;
  right: 8px;
  bottom: 8px;
}

.avatar-upload-button.mini {
  position: absolute;
  right: -4px;
  bottom: 0;
  padding: 0;
}

.profile-block h3 {
  font-size: 18px;
  line-height: 1.3;
}

.info-section {
  padding: 18px 0 0;
}

.section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
}

.section-title h4 {
  font-size: 14px;
  text-transform: uppercase;
  color: #596779;
  letter-spacing: 0;
}

.profile-title-row {
  min-width: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 5px;
}

.profile-title-row h3 {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.profile-nickname-button {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  cursor: pointer;
  flex: 0 0 auto;
}

.profile-nickname-button:hover {
  background: var(--brand-soft);
}

.conversation-setting-actions {
  display: grid;
  gap: 7px;
}

.conversation-setting-actions button {
  min-height: 38px;
  display: flex;
  align-items: center;
  gap: 9px;
  border-radius: 8px;
  padding: 7px 10px;
  background: #f5f7fb;
  color: #334155;
  cursor: pointer;
  text-align: left;
  font-weight: 750;
}

.conversation-setting-actions button.active {
  background: var(--brand-soft);
  color: var(--brand-dark);
}

.conversation-setting-actions button:disabled {
  cursor: wait;
  opacity: 0.65;
}

@keyframes typingPulse {
  0%, 60%, 100% {
    opacity: 0.35;
    transform: translateY(0);
  }
  30% {
    opacity: 1;
    transform: translateY(-2px);
  }
}

.section-text-button {
  border-radius: 8px;
  padding: 5px 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  cursor: pointer;
  font-size: 12px;
  font-weight: 850;
}

.section-text-button:hover {
  background: var(--brand-soft);
}

.member-list,
.shared-files {
  display: grid;
  gap: 8px;
}

.member-count-button {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 0;
  background: transparent;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.member-count-button svg {
  color: var(--brand-dark);
}

.member-item {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  padding: 5px;
  border-radius: 8px;
  cursor: pointer;
  transition: background-color 0.18s ease;
}

.member-item:hover,
.member-item:focus-visible {
  outline: 0;
  background: var(--brand-softest);
}

.member-meta {
  min-width: 0;
  flex: 1;
  display: grid;
}

.member-item strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.member-action-button {
  width: 30px;
  height: 30px;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand-dark);
  cursor: pointer;
}

.member-action-button:hover {
  background: var(--brand-soft);
}

.member-action-button.danger {
  background: #fff1f2;
  color: #e11d48;
}

.member-action-button.danger:hover {
  background: #ffe4e6;
}

.shared-files a,
.shared-files button {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  padding: 8px;
  border-radius: 8px;
  background: #f5f7fb;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.shared-files a > span:last-child,
.shared-files button > span:last-child {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.shared-files button > span:last-child {
  display: grid;
  gap: 2px;
}

.shared-files button strong,
.shared-files button em {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.shared-files button em {
  color: #7b8798;
  font-size: 12px;
  font-style: normal;
}

.shared-media-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 6px;
}

.shared-media-item {
  position: relative;
  aspect-ratio: 1;
  overflow: hidden;
  border-radius: 8px;
  background: #f5f7fb;
}

.shared-media-preview {
  width: 100%;
  height: 100%;
  display: grid;
  place-items: center;
  color: var(--brand);
}

.shared-media-grid img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.shared-media-download {
  top: 5px;
  right: 5px;
  width: 28px;
  height: 28px;
}

.shared-file-icon {
  width: 28px;
  height: 28px;
  position: relative;
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: var(--brand-softest);
  color: var(--brand);
}

.shared-file-icon.excel {
  background: #e7f7ed;
  color: #16803d;
}

.shared-file-icon.ppt {
  background: #fff0e8;
  color: #d45a16;
}

.shared-file-icon.pdf {
  background: #ffecec;
  color: #dc2626;
}

.shared-file-icon.archive,
.shared-file-icon.folder {
  background: #fff7dd;
  color: #b77900;
}

.shared-file-icon.audio,
.shared-file-icon.voice,
.shared-file-icon.video,
.shared-file-icon.code {
  background: #f0edff;
  color: #6d4aff;
}

.shared-file-icon.link {
  background: var(--brand-softest);
  color: var(--brand-dark);
}

.shared-file-icon.poll {
  background: #ecfdf5;
  color: #047857;
}

.dialog-form {
  display: grid;
  gap: 10px;
}

.profile-settings {
  display: grid;
  gap: 18px;
}

.member-profile-card {
  display: grid;
  justify-items: center;
  gap: 6px;
  padding: 8px 0 4px;
  text-align: center;
}

.member-profile-card > strong {
  margin-top: 6px;
  color: #172033;
  font-size: 18px;
}

.member-profile-card > span {
  color: #64748b;
  font-size: 13px;
}

.member-profile-presence {
  color: #64748b;
  font-size: 12px;
  font-weight: 750;
}

.member-profile-presence.online {
  color: #15803d;
}

.member-profile-actions {
  width: 100%;
  display: flex;
  justify-content: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 14px;
}

.member-profile-actions .dialog-button {
  display: inline-flex;
  align-items: center;
  gap: 7px;
}

.language-form {
  padding-bottom: 16px;
  border-bottom: 1px solid #edf1f6;
}

.language-selector {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
}

.language-selector button {
  min-width: 0;
  min-height: 46px;
  display: grid;
  grid-template-columns: 28px minmax(0, 1fr);
  align-items: center;
  gap: 8px;
  border-radius: 8px;
  padding: 7px 8px;
  background: #f5f7fb;
  color: #334155;
  cursor: pointer;
  text-align: left;
}

.language-selector button.active {
  background: var(--brand-soft);
  color: var(--brand-dark);
  box-shadow: inset 0 0 0 1px var(--brand-focus);
}

.language-selector span {
  width: 28px;
  height: 28px;
  display: grid;
  place-items: center;
  border-radius: 8px;
  background: #ffffff;
  color: inherit;
  font-size: 11px;
  font-weight: 900;
}

.language-selector strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
  line-height: 1.2;
}

.password-action-form {
  padding-top: 16px;
  border-top: 1px solid #edf1f6;
}

.password-open-button {
  width: 100%;
  min-height: 42px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border-radius: 8px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  cursor: pointer;
  font-weight: 850;
}

.password-open-button:hover {
  background: #d7fbff;
}

.password-dialog-form {
  padding-top: 0;
}

.avatar-editor {
  display: grid;
  justify-items: center;
  gap: 10px;
  padding-bottom: 4px;
}

.avatar-upload-button {
  height: 34px;
  display: inline-flex;
  align-items: center;
  gap: 7px;
  border-radius: 8px;
  padding: 0 12px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  cursor: pointer;
  font-weight: 700;
}

.password-form {
  padding-top: 16px;
  border-top: 1px solid #edf1f6;
}

.full-width {
  width: 100%;
}

.dialog-form label {
  color: #334155;
  font-weight: 700;
}

.dialog-form > input,
.dialog-form > select {
  height: 40px;
  border: 1px solid #dce3ee;
  border-radius: 8px;
  padding: 0 10px;
}

.poll-option-editor {
  display: grid;
  gap: 8px;
}

.poll-option-input {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 34px;
  gap: 7px;
}

.poll-option-input input {
  min-width: 0;
  height: 38px;
  border: 1px solid #dce3ee;
  border-radius: 8px;
  padding: 0 10px;
}

.poll-option-input button,
.poll-add-option {
  height: 34px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  border-radius: 8px;
  background: #edf2f7;
  color: #334155;
  cursor: pointer;
  font-weight: 800;
}

.poll-option-input button:disabled {
  cursor: not-allowed;
  opacity: 0.45;
}

.poll-add-option {
  width: fit-content;
  padding: 0 12px;
  background: var(--brand-soft);
  color: var(--brand-dark);
}

.poll-settings {
  display: grid;
  gap: 9px;
  padding-top: 4px;
}

.poll-settings label {
  display: flex;
  align-items: center;
  gap: 9px;
  font-weight: 700;
}

.poll-settings input {
  accent-color: var(--brand);
}

.chip-input {
  height: 42px;
  padding-left: 10px;
}

.chip-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.lookup-list {
  display: grid;
  gap: 4px;
  border-top: 1px solid #edf1f6;
  padding-top: 8px;
}

.contact-picker {
  display: grid;
  gap: 8px;
  padding-top: 8px;
  border-top: 1px solid #edf1f6;
}

.picker-list {
  max-height: 180px;
  min-height: 0;
  overflow-y: auto;
  display: grid;
  gap: 6px;
}

.picker-list button {
  min-height: 40px;
  display: flex;
  align-items: center;
  gap: 9px;
  border-radius: 8px;
  padding: 6px 8px;
  background: #f5f7fb;
  color: #172033;
  cursor: pointer;
  text-align: left;
}

.picker-list button.selected {
  background: var(--brand-soft);
  color: var(--brand-dark);
  box-shadow: inset 0 0 0 1px var(--brand-focus);
}

.picker-list span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dialog-button {
  min-width: 82px;
  height: 36px;
  border-radius: 8px;
  padding: 0 14px;
  cursor: pointer;
  font-weight: 700;
}

.dialog-button.ghost {
  background: #edf2f7;
  color: #243044;
}

.dialog-button.primary {
  background: var(--brand);
  color: #ffffff;
}

:deep(.el-dialog) {
  border-radius: 8px;
}

@keyframes messageEnter {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

:deep(.el-avatar) {
  flex: 0 0 auto;
  background: var(--brand-soft);
  color: var(--brand-dark);
  font-weight: 800;
}

::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background: #c4cfdd;
  border-radius: 8px;
}

@media (max-width: 1180px) {
  .chat-shell {
    grid-template-columns: 72px minmax(280px, 340px) minmax(0, 1fr);
  }

  .info-panel {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    z-index: 13000;
    width: min(336px, calc(100vw - 28px));
    display: block;
    transform: translateX(104%);
    transition: transform 0.22s ease;
    box-shadow: -24px 0 60px rgba(15, 23, 42, 0.22);
  }

  .chat-shell.show-info .info-panel {
    transform: translateX(0);
  }

  .info-backdrop {
    position: fixed;
    inset: 0;
    z-index: 12900;
    display: none;
    background: rgba(15, 23, 42, 0.32);
    cursor: pointer;
  }

  .chat-shell.show-info .info-backdrop {
    display: block;
  }

  .info-panel-close {
    position: sticky;
    top: 0;
    z-index: 2;
    width: 34px;
    height: 34px;
    margin: 0 0 8px auto;
    display: grid;
    place-items: center;
    border-radius: 8px;
    background: #f0f4fa;
    color: #243044;
    cursor: pointer;
  }
}

@media (max-width: 820px) {
.call-panel {
    top: 10px;
    right: 10px;
    left: 10px;
    width: auto;
  }

  .chat-shell {
    grid-template-columns: 1fr;
    height: 100vh;
    height: 100dvh;
  }

  .app-rail {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 12800;
    height: 64px;
    height: calc(64px + env(safe-area-inset-bottom));
    flex-direction: row;
    justify-content: space-between;
    padding: 8px 12px calc(8px + env(safe-area-inset-bottom));
    box-shadow: 0 -14px 34px rgba(15, 23, 42, 0.18);
  }

  .rail-logo {
    display: none;
  }

  .rail-actions,
  .rail-bottom {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0;
  }

  .rail-button {
    width: 44px;
    height: 44px;
  }

  .language-rail-button span {
    right: 6px;
    bottom: 5px;
  }

  .conversation-panel,
  .chat-pane {
    grid-column: 1;
    grid-row: 1;
    height: calc(100vh - 64px);
    height: calc(100dvh - 64px - env(safe-area-inset-bottom));
    padding-bottom: 0;
  }

  .chat-shell:not(.has-active) .chat-pane {
    grid-column: 1;
  }

  .chat-pane {
    display: none;
  }

  .chat-shell.has-active .conversation-panel {
    display: none;
  }

  .chat-shell.has-active .app-rail {
    display: none;
  }

  .chat-shell.has-active .conversation-panel,
  .chat-shell.has-active .chat-pane {
    height: 100vh;
    height: 100dvh;
  }

  .chat-shell.has-active .chat-pane {
    display: flex;
  }

  .chat-shell.show-directory .conversation-panel {
    display: none;
  }

  .chat-shell.show-directory .chat-pane {
    display: flex;
  }

  .panel-header {
    height: 76px;
    padding: 14px 14px 10px;
  }

  .panel-header h1 {
    font-size: 21px;
  }

  .search-box {
    margin: 0 14px 10px;
  }

  .directory-header {
    height: 64px;
    padding: 0 16px;
  }

  .directory-content {
    padding: 16px 14px;
  }

  .directory-tabs {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 6px;
  }

  .directory-tabs button {
    height: 38px;
    border-radius: 8px;
    background: #f0f4fa;
    color: #334155;
    cursor: pointer;
    font-weight: 800;
  }

  .directory-tabs button.active {
    background: var(--brand-soft);
    color: var(--brand-dark);
  }

  .mobile-back {
    display: grid;
    place-items: center;
  }

  .chat-header {
    min-height: 64px;
    height: auto;
    flex-wrap: wrap;
    gap: 9px;
    padding: 8px 10px;
  }

  .chat-title h2 {
    font-size: 15px;
  }

  .chat-title span {
    font-size: 12px;
  }

  .chat-actions {
    gap: 4px;
  }

  .conversation-search {
    order: 5;
    width: 100%;
    min-width: 0;
    height: 36px;
  }

  .chat-actions .icon-button,
  .mobile-back {
    width: 34px;
    height: 34px;
  }

  .message-list {
    padding: 16px 12px;
  }

  .message-stack {
    max-width: 84%;
  }

  .attachment-item {
    min-width: min(330px, 82vw);
  }

  .voice-player {
    min-width: min(320px, 82vw);
  }

  .image-grid {
    grid-template-columns: repeat(2, minmax(0, 136px));
  }

  .image-grid img {
    height: 122px;
  }

  .image-grid.compact {
    grid-template-columns: repeat(2, minmax(0, 104px));
  }

  .image-grid.compact img {
    height: 96px;
  }

  .composer-body {
    grid-template-columns: minmax(0, 1fr) auto;
  }

  .composer-tools {
    grid-column: 1 / -1;
  }

  .composer {
    padding: 9px 10px calc(10px + env(safe-area-inset-bottom));
  }

  .notification-stack {
    right: 10px;
    bottom: calc(76px + env(safe-area-inset-bottom));
  }

  .info-panel {
    width: min(336px, calc(100vw - 22px));
    bottom: calc(64px + env(safe-area-inset-bottom));
  }

  .info-backdrop {
    bottom: calc(64px + env(safe-area-inset-bottom));
  }

  .chat-shell.has-active .notification-stack {
    bottom: calc(14px + env(safe-area-inset-bottom));
  }

  .chat-shell.has-active .info-panel,
  .chat-shell.has-active .info-backdrop {
    bottom: 0;
  }
}

.reminder-call-panel {
  position: fixed;
  inset: 0;
  z-index: 16000;
  display: grid;
  place-items: center;
  padding: 28px;
  background: rgba(17, 24, 39, 0.96);
  color: #ffffff;
}

.reminder-call-card {
  position: relative;
  width: min(420px, 100%);
  min-height: 360px;
  display: grid;
  justify-items: center;
  align-content: center;
  gap: 12px;
  overflow: hidden;
  border-radius: 14px;
  padding: 34px 24px 44px;
  text-align: center;
  background: rgba(255, 255, 255, 0.08);
  box-shadow: 0 26px 80px rgba(0, 0, 0, 0.36);
}

.reminder-call-pulse {
  width: 86px;
  height: 86px;
  display: grid;
  place-items: center;
  border-radius: 999px;
  background: #0891b2;
  box-shadow: 0 0 0 0 rgba(8, 145, 178, 0.42);
  animation: callPulse 1.5s infinite;
}

.reminder-call-card small,
.reminder-call-time {
  color: rgba(255, 255, 255, 0.72);
  font-weight: 800;
}

.reminder-call-card strong {
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  font-size: 24px;
  line-height: 1.25;
}

.reminder-call-card .call-control {
  margin-top: 28px;
}

.reminder-call-card > i { position: absolute; left: 0; right: 0; bottom: 0; height: 4px; background: #ffffff; animation: reminder-countdown 5s linear forwards; transform-origin: left; }

@keyframes reminder-countdown { to { transform: scaleX(0); } }

.scheduled-reminder-list {
  max-height: min(60vh, 520px);
  display: grid;
  gap: 6px;
  margin-top: 16px;
  overflow-y: auto;
}

.scheduled-reminder-list > div {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 9px;
  padding: 9px;
  border-radius: 8px;
  background: #f6f8fb;
  color: var(--brand-dark);
}

.scheduled-reminder-list span { min-width: 0; display: grid; gap: 2px; }
.scheduled-reminder-list strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #172033; }
.scheduled-reminder-list small { color: #64748b; }
.scheduled-reminder-list button { width: 30px; height: 30px; display: grid; place-items: center; border-radius: 8px; color: #64748b; cursor: pointer; }
.reminder-empty { padding: 18px 0 4px; text-align: center; }
</style>
