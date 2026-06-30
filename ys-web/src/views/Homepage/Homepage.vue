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
                <span class="conversation-name">{{ conversation.name }}</span>
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
                <span class="conversation-name">{{ conversation.name }}</span>
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
            <el-tooltip v-if="activeConversation.type === 'group'" :content="homeT('chat.addMember')" placement="bottom">
              <button class="icon-button" type="button" @click="openAddMemberDialog">
                <UserPlus :size="20" />
              </button>
            </el-tooltip>
            <el-tooltip :content="homeT('chat.info')" placement="bottom">
              <button class="icon-button" type="button" @click="infoPanelOpen = true">
                <Info :size="20" />
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
          <button
            class="pinned-message-remove"
            type="button"
            :title="homeT('chat.unpinMessage')"
            @click="unpinActiveMessage"
          >
            <X :size="15" />
          </button>
        </div>

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
            }"
          >
            <div v-if="!isOwnMessage(message) && !isCenteredMessage(message)" class="avatar-presence-wrap message-avatar-wrap">
              <el-avatar :size="32" :src="message.senderAvatar || undefined">
                {{ initials(message.senderName) }}
              </el-avatar>
              <span
                class="presence-dot small"
                :class="{ online: isUserOnline(presenceUserByUserid(message.senderUserid)) }"
                :title="presenceLabel(presenceUserByUserid(message.senderUserid))"
              ></span>
            </div>

            <div class="message-stack">
              <span
                v-if="activeConversation.type === 'group' && !isOwnMessage(message) && !isCenteredMessage(message)"
                class="sender-name"
              >
                {{ message.senderName }}
              </span>

              <div class="message-content-row">
                <div class="message-bubble" :class="message.type">
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

                <div v-if="message.type === 'system'" class="system-notice">
                  {{ message.content }}
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
                        @click="isPinnedMessage(message) ? unpinActiveMessage() : pinMessage(message)"
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
                  <span
                    v-for="(part, index) in messageTextParts(message.content)"
                    :key="`${message.id}-${index}`"
                    :class="{ mention: part.isMention }"
                  >
                    {{ part.text }}
                  </span>
                </p>

                <div v-if="imageAttachments(message).length" class="image-grid">
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

                <div v-if="voiceAttachments(message).length" class="voice-list">
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

                <div v-if="fileAttachments(message).length" class="attachment-list">
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

                <time>{{ formatTime(message.createdAt) }}</time>
              </div>
              <div v-if="!isCenteredMessage(message)" class="message-actions">
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
                    </el-dropdown-menu>
                  </template>
                </el-dropdown>
                </div>
              </div>
            </div>
          </div>
          </template>
        </section>

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
                  :key="member.userid"
                  :class="{ selected: index === mentionSelectedIndex }"
                  type="button"
                  @mousedown.prevent="insertMention(member)"
                >
                  <el-avatar :size="28" :src="member.avatar || undefined">
                    {{ initials(displayName(member)) }}
                  </el-avatar>
                  <span>
                    <strong>{{ displayName(member) }}</strong>
                    <small>{{ member.userid }}</small>
                  </span>
                </button>
              </div>

              <textarea
                ref="composerInputRef"
                v-model="composerText"
                rows="1"
                :placeholder="homeT('chat.composerPlaceholder')"
                @input="updateMentionState"
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
          v-if="activeConversation.type === 'group'"
          class="conversation-cover"
          :class="{ empty: !activeConversation.background }"
        >
          <img v-if="activeConversation.background" :src="activeConversation.background" alt="" />
          <button
            v-if="isCurrentUserGroupOwner"
            class="cover-upload-button"
            type="button"
            @click="groupBackgroundInputRef?.click()"
          >
            <Camera :size="15" />
          </button>
        </div>
        <div class="conversation-avatar-editor" :class="{ 'with-cover': activeConversation.type === 'group' }">
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
            v-if="isCurrentUserGroupOwner"
            class="avatar-upload-button mini"
            type="button"
            @click="groupAvatarInputRef?.click()"
          >
            <Camera :size="15" />
          </button>
        </div>
        <h3>{{ activeConversation.name }}</h3>
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
        <span>{{ activeConversation.memberCount }} {{ homeT("chat.members") }}</span>
      </div>

      <section class="info-section">
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
        <div v-if="activeConversation.type !== 'group' || membersExpanded" class="member-list">
          <div v-for="member in activeConversation.members" :key="member.userid" class="member-item">
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
                @click="openNicknameDialog(member)"
              >
                <Pencil :size="15" />
              </button>
            </el-tooltip>
            <el-tooltip
              v-if="isCurrentUserGroupOwner && member.userid !== currentUserid"
              :content="homeT('info.removeMember')"
              placement="left"
            >
              <button
                class="member-action-button danger"
                type="button"
                :aria-label="homeT('info.removeMemberFromGroup', { name: member.fullname || member.userid })"
                @click="removeMemberFromGroup(member)"
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
              :class="{ selected: groupMemberUserids.includes(contact.userid) }"
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
              :class="{ selected: addMemberUserids.includes(contact.userid) }"
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
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useI18n } from "vue-i18n";
import { ElMessage, ElMessageBox } from "element-plus";
import dayjs from "dayjs";
import { Capacitor } from "@capacitor/core";
import { PushNotifications } from "@capacitor/push-notifications";
import BrandLogo from "@/components/BrandLogo.vue";
import {
  Camera,
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
  Info,
  KeyRound,
  Link2,
  ListChecks,
  Languages,
  LogOut,
  MessageCircle,
  Mic,
  MoreHorizontal,
  Paperclip,
  Pencil,
  Pin,
  Plus,
  Presentation,
  Reply,
  Search,
  SendHorizontal,
  Square,
  Trash2,
  UploadCloud,
  UserPlus,
  UserRound,
  Users,
  X,
} from "lucide-vue-next";
import chatApi from "@/store/chat";

const router = useRouter();
const { t, locale } = useI18n();
const enableNativePush = import.meta.env.VITE_ENABLE_PUSH === "true";
const fallbackRefreshMs = 60 * 1000;
const currentUserid = localStorage.getItem("userid") || "";
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
const pinnedMessages = ref({});
const toastNotifications = ref([]);
const loadingConversations = ref(false);
const loadingContacts = ref(false);
const loadingMessages = ref(false);
const loadingOlderMessages = ref(false);
const messagesHasMore = ref(false);
const sending = ref(false);
const uploading = ref(false);
const isDragging = ref(false);
const dragDepth = ref(0);
const searchKeyword = ref("");
const searchScope = ref("all");
const contactSearchKeyword = ref("");
const chatSearchResults = ref({ contacts: [], messages: [], files: [] });
const searchingChat = ref(false);
const conversationSearchKeyword = ref("");
const conversationSearchIndex = ref(0);
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
const contactDialogVisible = ref(false);
const contactUserid = ref("");
const contactLookupUsers = ref([]);
const contactLookupLoading = ref(false);
const profileDialogVisible = ref(false);
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
let refreshTimer = null;
let searchTimer = null;
let contactLookupTimer = null;
let realtimeSocket = null;
let realtimeReconnectTimer = null;
let backgroundSyncPromise = null;
let pushListenersRegistered = false;
let pushListenerHandles = [];
let searchRequestId = 0;
let contactLookupRequestId = 0;
let componentUnmounted = false;
let mediaRecorder = null;
let recordingStream = null;
let recordingChunks = [];
let recordingTimer = null;
let recordingStartedAt = 0;
let discardRecording = false;
const readStateStorageKey = `ys_chat_read_state_${currentUserid}`;
const unreadStorageKey = `ys_chat_unread_counts_${currentUserid}`;
const pinnedMessagesStorageKey = `ys_chat_pinned_messages_${currentUserid}`;

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
const activePinnedMessage = computed(() => pinnedMessages.value[String(activeConversationId.value)] || null);

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
  if (shouldShowSearchSection("messages") && chatSearchMessages.value.length) return true;
  if (shouldShowSearchSection("files") && chatSearchFiles.value.length) return true;
  return false;
});

const conversationSearchMatches = computed(() => {
  const keyword = normalizeDirectoryText(conversationSearchKeyword.value);
  if (!keyword) return [];
  return messages.value.filter((message) => messageMatchesKeyword(message, keyword));
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
    backgroundImage: `linear-gradient(rgba(248, 250, 252, 0.84), rgba(248, 250, 252, 0.84)), url("${cssUrl(background)}")`,
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
    (member) => member.userid === currentUserid && member.role === "owner",
  );
});

const shouldShowPresence = (user = {}) => Boolean(user.userid && user.userid !== currentUserid);
const isUserOnline = (user = {}) => Boolean(user.isOnline);
const presenceLabel = (user = {}) => homeT(isUserOnline(user) ? "presence.online" : "presence.offline");

const conversationPresenceUser = (conversation = {}) => {
  if (conversation.type !== "direct") return null;
  return (conversation.members || []).find((member) => member.userid !== currentUserid) || null;
};

const presenceUserByUserid = (userid) =>
  activeConversation.value?.members?.find((member) => member.userid === userid) || { userid, isOnline: false };

const applyPresence = (userid, isOnline) => {
  const updateUser = (user) => (user?.userid === userid ? { ...user, isOnline } : user);

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
  return members
    .filter((member) => member.userid !== currentUserid)
    .filter((member) => {
      if (!keyword) return true;
      return `${member.fullname} ${member.nickname || ""} ${member.userid}`.toLowerCase().includes(keyword);
    })
    .slice(0, 6);
});

onMounted(async () => {
  readState.value = loadStoredObject(readStateStorageKey);
  unreadCounts.value = loadStoredObject(unreadStorageKey);
  pinnedMessages.value = loadStoredObject(pinnedMessagesStorageKey);
  await loadProfile();
  await loadContacts();
  await loadConversations(false);
  connectRealtime();
  await initPushNotifications();
  document.addEventListener("visibilitychange", syncAfterVisibilityReturn);
  window.addEventListener("online", syncAfterNetworkReturn);
});

onBeforeUnmount(() => {
  componentUnmounted = true;
  stopFallbackRefresh();
  if (searchTimer) window.clearTimeout(searchTimer);
  if (contactLookupTimer) window.clearTimeout(contactLookupTimer);
  document.removeEventListener("visibilitychange", syncAfterVisibilityReturn);
  window.removeEventListener("online", syncAfterNetworkReturn);
  cancelVoiceRecording();
  disconnectRealtime();
  removePushListeners();
});

watch([searchKeyword, searchScope], ([value, scope]) => {
  if (searchTimer) window.clearTimeout(searchTimer);
  const keyword = value.trim();
  if (!keyword) {
    searchRequestId += 1;
    chatSearchResults.value = { contacts: [], messages: [], files: [] };
    searchingChat.value = false;
    if (scope !== "all") searchScope.value = "all";
    return;
  }

  searchingChat.value = true;
  searchTimer = window.setTimeout(() => searchChatRealtime(keyword, scope), 250);
});

watch(conversationSearchKeyword, async () => {
  conversationSearchIndex.value = 0;
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

watch(activeConversationId, () => {
  conversationSearchKeyword.value = "";
  conversationSearchIndex.value = 0;
  infoPanelView.value = "details";
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

const persistPinnedMessages = () => {
  localStorage.setItem(pinnedMessagesStorageKey, JSON.stringify(pinnedMessages.value));
};

const unreadCount = (conversationId) => Number(unreadCounts.value[conversationId] || 0);

const formatUnreadCount = (conversationId) => {
  const count = unreadCount(conversationId);
  if (count > 99) return "99+";
  return String(count);
};

const markConversationRead = (conversationId) => {
  const conversation = conversations.value.find((item) => item.id === conversationId);
  const lastMessageID = conversation?.lastMessage?.id || lastMessageIds.value[conversationId] || 0;
  unreadCounts.value = { ...unreadCounts.value, [conversationId]: 0 };
  readState.value = { ...readState.value, [conversationId]: lastMessageID };
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
    const lastReadMessageId = Number(readState.value[conversationId] || 0);
    const isNewMessage = previousLastMessageId && lastMessage.id !== previousLastMessageId;
    const isUnreadFromStorage = isInitialLoad && lastReadMessageId > 0 && lastMessage.id > lastReadMessageId;
    const fromOtherUser = lastMessage.senderUserid !== currentUserid;
    const isActiveConversation = conversationId === activeConversationId.value;

    if (fromOtherUser && (isNewMessage || isUnreadFromStorage)) {
      if (!isActiveConversation) {
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

const connectRealtime = () => {
  if (componentUnmounted || !localStorage.getItem("user_token") || realtimeSocket) return;

  try {
    realtimeSocket = new WebSocket(chatApi.getRealtimeUrl());
  } catch {
    startFallbackRefresh();
    scheduleRealtimeReconnect();
    return;
  }

  realtimeSocket.onopen = () => {
    stopFallbackRefresh();
    void syncChatSnapshot();
  };

  realtimeSocket.onmessage = (event) => {
    try {
      handleRealtimeEvent(JSON.parse(event.data));
    } catch {
      // Ignore malformed realtime frames; reconnect and focused-window sync remain the fallback.
    }
  };

  realtimeSocket.onclose = () => {
    realtimeSocket = null;
    startFallbackRefresh();
    scheduleRealtimeReconnect();
  };

  realtimeSocket.onerror = () => {
    realtimeSocket?.close();
  };
};

const scheduleRealtimeReconnect = () => {
  if (componentUnmounted || realtimeReconnectTimer) return;
  realtimeReconnectTimer = window.setTimeout(() => {
    realtimeReconnectTimer = null;
    connectRealtime();
  }, 2500);
};

const disconnectRealtime = () => {
  if (realtimeReconnectTimer) {
    window.clearTimeout(realtimeReconnectTimer);
    realtimeReconnectTimer = null;
  }
  if (realtimeSocket) {
    const socket = realtimeSocket;
    realtimeSocket = null;
    socket.onclose = null;
    socket.close();
  }
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

  backgroundSyncPromise = (async () => {
    await loadConversations(false, { silent: true });
    if (activeConversationId.value) {
      await loadMessages(activeConversationId.value, false);
    }
  })().finally(() => {
    backgroundSyncPromise = null;
  });

  return backgroundSyncPromise;
};

const syncAfterVisibilityReturn = () => {
  if (document.visibilityState !== "visible") return;
  connectRealtime();
  void syncChatSnapshot();
};

const syncAfterNetworkReturn = () => {
  connectRealtime();
  void syncChatSnapshot();
};

const handleRealtimeEvent = async (event) => {
  if (event?.type === "chat.presence.changed" && event.userid) {
    applyPresence(event.userid, Boolean(event.isOnline));
    return;
  }

  if (event?.type === "chat.poll.updated" && event.message?.id) {
    if (event.message.conversationId === activeConversationId.value) {
      upsertMessage(event.message);
      await scrollToBottom();
    }
    return;
  }

  if (event?.type !== "chat.message.created" || !event.message?.id) return;

  const message = event.message;
  if (message.conversationId === activeConversationId.value) {
    const exists = messages.value.some((item) => item.id === message.id);
    if (!exists) {
      messages.value = sortMessagesForDisplay([...messages.value, message]);
      await scrollToBottom();
    }
  }

  await loadConversations(false, { silent: true });
};

const initPushNotifications = async () => {
  if (!enableNativePush || !Capacitor.isNativePlatform() || pushListenersRegistered) return;

  try {
    const permission = await PushNotifications.requestPermissions();
    if (permission.receive !== "granted") return;

    pushListenersRegistered = true;
    const registrationHandle = await PushNotifications.addListener("registration", async (token) => {
      try {
        await chatApi.registerDeviceToken(token.value, Capacitor.getPlatform());
      } catch (error) {
        showApiError(error);
      }
    });
    pushListenerHandles.push(registrationHandle);

    const actionHandle = await PushNotifications.addListener("pushNotificationActionPerformed", async (action) => {
      const conversationId = Number(action.notification?.data?.conversationId || 0);
      if (!conversationId) return;
      await openConversationById(conversationId);
    });
    pushListenerHandles.push(actionHandle);

    await PushNotifications.register();
  } catch {
    // Push setup can fail on emulators without Play Services; chat still works through realtime/polling.
  }
};

const removePushListeners = () => {
  pushListenerHandles.forEach((handle) => {
    void handle.remove();
  });
  pushListenerHandles = [];
  pushListenersRegistered = false;
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
};

const clearConversationSearch = () => {
  conversationSearchKeyword.value = "";
  conversationSearchIndex.value = 0;
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

const isContactUser = (userid) => contacts.value.some((contact) => contact.userid === userid);

const withContactState = (user) => ({
  ...user,
  isContact: Boolean(user.isContact) || isContactUser(user.userid),
});

const sortUsers = (users) =>
  [...users].sort((first, second) =>
    (first.fullname || first.userid || "").localeCompare(second.fullname || second.userid || "", sortLocale.value),
  );

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
    const res = await chatApi.searchChat(keyword, scope);
    if (requestId !== searchRequestId || keyword !== searchKeyword.value.trim() || scope !== searchScope.value) return;
    const results = res.data?.results || {};
    chatSearchResults.value = {
      contacts: (results.contacts || []).map(withContactState),
      messages: results.messages || [],
      files: results.files || [],
    };
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
    contactLookupUsers.value = (res.data?.users || []).map(withContactState).slice(0, 5);
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
  const withoutCurrent = contacts.value.filter((item) => item.userid !== nextContact.userid);
  contacts.value = sortUsers([...withoutCurrent, nextContact]);
  chatSearchResults.value = {
    ...chatSearchResults.value,
    contacts: (chatSearchResults.value.contacts || []).map((user) =>
      user.userid === nextContact.userid ? { ...user, isContact: true } : user,
    ),
  };
  contactLookupUsers.value = contactLookupUsers.value.map((user) =>
    user.userid === nextContact.userid ? { ...user, isContact: true } : user,
  );
};

const addContactByUserid = async (userid) => {
  const contactUseridValue = String(userid || "").trim();
  if (!contactUseridValue) {
    ElMessage.warning(homeT("messages.enterUserid"));
    return null;
  }
  if (contactUseridValue === currentUserid) {
    ElMessage.warning(homeT("messages.cannotAddSelf"));
    return null;
  }

  const res = await chatApi.addContact(contactUseridValue);
  const contact = res.data?.contact;
  upsertContact(contact);
  ElMessage.success(homeT("messages.contactAdded"));
  return contact;
};

const addContactFromUser = async (user) => {
  try {
    await addContactByUserid(user.userid);
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
  if (!file || !activeConversationId.value || activeConversation.value?.type !== "group") return;

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
    const nextConversations = res.data?.conversations || [];
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
  if (message.type !== "poll") return createdAt;
  const pollUpdatedAt = dayjs(message.poll?.updatedAt).valueOf() || 0;
  return Math.max(createdAt, pollUpdatedAt);
};

const messageSortRank = (message = {}) => {
  if (message.type === "poll") return 2;
  if (message.type === "system") return 1;
  return 0;
};

const sortMessagesForDisplay = (messageList = []) =>
  messageList.slice().sort((first, second) => {
    const timeDiff = messageSortValue(first) - messageSortValue(second);
    if (timeDiff !== 0) return timeDiff;
    const rankDiff = messageSortRank(first) - messageSortRank(second);
    if (rankDiff !== 0) return rankDiff;
    return first.id - second.id;
  });

const mergeMessageLists = (currentMessages = [], nextMessages = []) => {
  const mergedById = new Map();
  currentMessages.forEach((message) => mergedById.set(message.id, message));
  nextMessages.forEach((message) => mergedById.set(message.id, message));
  return sortMessagesForDisplay(Array.from(mergedById.values()));
};

const loadMessages = async (conversationId, shouldScroll = true, options = {}) => {
  const replaceMessages = options.replace ?? shouldScroll;
  const requestId = replaceMessages ? ++messageRequestId : messageRequestId;
  try {
    if (shouldScroll) loadingMessages.value = true;
    const res = await chatApi.getMessages(conversationId, { limit: messagePageSize });
    if (requestId !== messageRequestId || conversationId !== activeConversationId.value) return;

    const nextMessages = res.data?.messages || [];
    const responseHasMore = Boolean(res.data?.hasMore);
    if (replaceMessages || messages.value.length === 0) {
      messages.value = sortMessagesForDisplay(nextMessages);
      messagesHasMore.value = responseHasMore;
    } else {
      messages.value = mergeMessageLists(messages.value, nextMessages);
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

const handleMessageListScroll = () => {
  const listEl = messageListRef.value;
  if (!listEl || listEl.scrollTop > 80) return;
  void loadOlderMessages();
};

const startDirectChat = async (userid) => {
  const targetUserid = String(userid || "").trim();
  if (!targetUserid) {
    ElMessage.warning(homeT("messages.enterChatUserid"));
    return;
  }
  if (targetUserid === currentUserid) {
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
  if (!groupMemberUserids.value.includes(userid) && userid !== currentUserid) {
    groupMemberUserids.value.push(userid);
  }
  groupMemberInput.value = "";
};

const removeGroupMemberChip = (userid) => {
  groupMemberUserids.value = groupMemberUserids.value.filter((item) => item !== userid);
};

const toggleGroupMember = (userid) => {
  if (!userid || userid === currentUserid) return;
  if (groupMemberUserids.value.includes(userid)) {
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
  if (!addMemberUserids.value.includes(userid) && !currentMemberUserids.includes(userid)) {
    addMemberUserids.value.push(userid);
  }
  addMemberInput.value = "";
};

const removeAddMemberChip = (userid) => {
  addMemberUserids.value = addMemberUserids.value.filter((item) => item !== userid);
};

const toggleAddMember = (userid) => {
  if (!userid || userid === currentUserid) return;
  const currentMemberUserids = activeConversation.value?.members?.map((member) => member.userid) || [];
  if (currentMemberUserids.includes(userid)) return;
  if (addMemberUserids.value.includes(userid)) {
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
  if (member.userid === currentUserid) return;

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

const openNicknameDialog = (member) => {
  if (!activeConversationId.value || !member?.userid) return;
  nicknameTarget.value = member;
  nicknameValue.value = member.nickname || "";
  nicknameDialogVisible.value = true;
};

const submitNickname = async () => {
  if (!activeConversationId.value || !nicknameTarget.value?.userid) return;

  try {
    await chatApi.updateConversationMemberNickname(
      activeConversationId.value,
      nicknameTarget.value.userid,
      nicknameValue.value,
    );
    nicknameDialogVisible.value = false;
    const conversationId = activeConversationId.value;
    await loadConversations(false);
    if (conversationId) {
      await loadMessages(conversationId, false);
    }
    ElMessage.success(nicknameValue.value ? homeT("messages.nicknameSaved") : homeT("messages.nicknameRemoved"));
  } catch (error) {
    showApiError(error);
  }
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
  const mentionText = `@${displayName(member) || member.userid} `;
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
    const messageRes = await chatApi.sendMessage(activeConversationId.value, {
      type: "voice",
      content: "",
      attachments,
    });
    if (messageRes.data?.message) {
      messages.value.push(messageRes.data.message);
    }
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

const isPinnedMessage = (message = {}) => activePinnedMessage.value?.id === message.id;

const pinMessage = (message = {}) => {
  if (!activeConversationId.value || !message.id) return;
  pinnedMessages.value = {
    ...pinnedMessages.value,
    [String(activeConversationId.value)]: {
      ...toMessageReference(message),
      createdAt: message.createdAt,
    },
  };
  persistPinnedMessages();
  ElMessage.success(homeT("messages.messagePinned"));
};

const unpinActiveMessage = () => {
  if (!activeConversationId.value) return;
  const nextPinnedMessages = { ...pinnedMessages.value };
  delete nextPinnedMessages[String(activeConversationId.value)];
  pinnedMessages.value = nextPinnedMessages;
  persistPinnedMessages();
  ElMessage.success(homeT("messages.messageUnpinned"));
};

const handleMessageOption = (command, message) => {
  if (command === "pin") {
    pinMessage(message);
    return;
  }
  if (command === "unpin") {
    unpinActiveMessage();
    return;
  }
  if (command === "copy") {
    void copyMessage(message);
  }
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
  if (!message?.id) return;
  const index = messages.value.findIndex((item) => item.id === message.id);
  if (index >= 0) {
    messages.value.splice(index, 1, message);
    messages.value = sortMessagesForDisplay(messages.value);
    return;
  }
  messages.value = sortMessagesForDisplay([...messages.value, message]);
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
  message.type === "poll" && message.poll?.createdBy === currentUserid && !message.poll?.isClosed;

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
    const res = await chatApi.sendMessage(forwardTargetConversationId.value, {
      type: message.type,
      content: message.content || "",
      forwardedFromMessageId: message.id,
      attachments: cloneAttachments(message.attachments || []),
    });
    forwardDialogVisible.value = false;
    forwardingMessage.value = null;
    if (forwardTargetConversationId.value === activeConversationId.value && res.data?.message) {
      messages.value.push(res.data.message);
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

  try {
    sending.value = true;
    const res = await chatApi.sendMessage(activeConversationId.value, {
      type,
      content,
      replyToMessageId: replyingTo.value?.id || 0,
      attachments: pendingAttachments.value,
    });
    if (res.data?.message) {
      messages.value.push(res.data.message);
    }
    composerText.value = "";
    cancelReply();
    pendingAttachments.value = [];
    await loadConversations(false);
    await scrollToBottom();
  } catch (error) {
    showApiError(error);
  } finally {
    sending.value = false;
  }
};

const scrollToBottom = async () => {
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

const scrollToMessage = async (messageId) => {
  await nextTick();
  const target = document.getElementById(`message-${messageId}`);
  if (!target) return;
  target.scrollIntoView({ behavior: "smooth", block: "center" });
  target.classList.add("highlight");
  window.setTimeout(() => target.classList.remove("highlight"), 1400);
};

const handleLogout = () => {
  disconnectRealtime();
  removePushListeners();
  localStorage.removeItem("user_token");
  localStorage.removeItem("userid");
  localStorage.removeItem("fullname");
  localStorage.removeItem("account_id");
  router.push("/login");
};

const isOwnMessage = (message) => message.senderUserid === currentUserid;

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

const messageReferencePreview = (message = {}) => {
  if (message.type === "system") return message.content || homeT("previews.system");
  if (message.type === "poll") return message.content || homeT("previews.poll");
  if (message.content) return message.content;
  if (message.type === "voice") return homeT("previews.voice");
  if (message.type === "folder") return homeT("previews.folderAttachment");
  if (message.type === "file") return homeT("previews.fileAttachment");
  if (message.type === "link") return homeT("previews.link");
  return homeT("previews.message");
};

const messageTextParts = (content = "") => {
  const labels = mentionLabels();
  if (!content || !labels.length) return [{ text: content, isMention: false }];

  const parts = [];
  const lowerContent = content.toLowerCase();
  let cursor = 0;

  while (cursor < content.length) {
    let nextMatch = null;
    for (const label of labels) {
      const index = lowerContent.indexOf(label.lower, cursor);
      if (index < 0) continue;
      if (!nextMatch || index < nextMatch.index || (index === nextMatch.index && label.text.length > nextMatch.text.length)) {
        nextMatch = { ...label, index };
      }
    }

    if (!nextMatch) {
      parts.push({ text: content.slice(cursor), isMention: false });
      break;
    }

    if (nextMatch.index > cursor) {
      parts.push({ text: content.slice(cursor, nextMatch.index), isMention: false });
    }
    parts.push({
      text: content.slice(nextMatch.index, nextMatch.index + nextMatch.text.length),
      isMention: true,
    });
    cursor = nextMatch.index + nextMatch.text.length;
  }

  return parts;
};

const mentionLabels = () => {
  const members = activeConversation.value?.members || [];
  const labels = [];
  const seen = new Set();

  members.forEach((member) => {
    [`@${displayName(member)}`, `@${member.fullname}`, `@${member.userid}`].forEach((label) => {
      const normalized = label.trim();
      if (normalized.length <= 1 || seen.has(normalized.toLowerCase())) return;
      seen.add(normalized.toLowerCase());
      labels.push({ text: normalized, lower: normalized.toLowerCase() });
    });
  });

  return labels.sort((first, second) => second.text.length - first.text.length);
};

const imageAttachments = (message) =>
  (message.attachments || []).filter((attachment) => isImageAttachment(attachment));

const voiceAttachments = (message) =>
  message.type === "voice"
    ? (message.attachments || []).filter((attachment) => isAudioAttachment(attachment))
    : [];

const fileAttachments = (message) =>
  (message.attachments || []).filter(
    (attachment) => !isImageAttachment(attachment) && !(message.type === "voice" && isAudioAttachment(attachment)),
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
  const prefix = message.senderUserid === currentUserid ? homeT("previews.youPrefix") : "";
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

.icon-button:hover,
.tool-button:hover {
  background: var(--brand-soft);
  color: var(--brand-dark);
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
.dialog-form input {
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
  grid-template-columns: minmax(0, 1fr) 32px;
  align-items: center;
  gap: 8px;
  padding: 6px 18px;
  border-bottom: 1px solid #dce3ee;
  background: #ffffff;
  flex: 0 0 auto;
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

.message-list {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 20px 28px;
  background-position: center;
  background-size: cover;
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
  color: #637083;
  font-size: 12px;
  font-weight: 600;
}

.message-bubble {
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

.message-stack:hover .message-bubble {
  box-shadow: 0 10px 24px rgba(15, 23, 42, 0.1);
  transform: translateY(-1px);
}

.message-row.own .message-bubble {
  background: var(--brand-soft);
  border-color: var(--brand-border);
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

.message-text {
  margin: 0;
  white-space: pre-wrap;
}

.message-text .mention {
  color: var(--brand-dark);
  font-weight: 800;
  background: var(--brand-tint);
  border-radius: 6px;
  padding: 1px 3px;
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

.image-card {
  position: relative;
  border-radius: 8px;
  overflow: hidden;
  background: #dce3ee;
  border: 1px solid rgba(0, 0, 0, 0.05);
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

.dialog-form > input {
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
  .chat-shell {
    grid-template-columns: 1fr;
    height: 100dvh;
  }

  .app-rail {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 12800;
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
</style>
