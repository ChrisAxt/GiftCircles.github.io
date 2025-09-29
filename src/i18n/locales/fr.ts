// src/i18n/fr.ts
const fr = {
  translation: {
    // for the language picker (native self-name)
    languages: {
      nativeNames: { fr: 'Français' },
    },

    titles: {
      event: 'Détails de l’event',
      createEvent: 'Créer un event',
      joinEvent: 'Rejoindre un event',
      editEvent: 'Modifier l’event',
      list: 'Listes',
      addItem: 'Ajouter un article',
      createList: 'Créer une liste',
    },

    profile: {
      title: 'Profil',
      email: 'E-mail',
      displayName: 'Nom d’affichage',
      saveName: 'Enregistrer le nom',
      memberSince: 'Membre depuis',
      stats: { events: 'Événements', listsCreated: 'Listes créées' },
      account: 'Compte',
      signOut: 'Se déconnecter',
      dangerTitle: 'Zone dangereuse',
      dangerDesc: 'Cela supprimera définitivement votre profil et vous retirera des événements.',
      delete: 'Supprimer le compte',
      alerts: {
        nameRequiredTitle: 'Nom requis',
        nameRequiredBody: 'Veuillez saisir un nom d’affichage.',
        saveOkTitle: 'Enregistré',
        saveOkBody: 'Votre nom d’affichage a été mis à jour.',
        saveErrTitle: 'Échec de l’enregistrement',
        signOutErrTitle: 'Échec de la déconnexion',
        deleteConfirmTitle: 'Supprimer votre compte ?',
        deleteConfirmBody: 'Cela supprimera définitivement votre profil, vos adhésions et vous déconnectera.',
        cancel: 'Annuler',
        confirmDelete: 'Supprimer',
        deleteErrTitle: 'Échec de la suppression',
        deleteOkTitle: 'Compte supprimé',
        deleteOkBody: 'Votre compte a été supprimé.',
      },
      settings: { title: 'Réglages', appearance: 'Apparence', language: 'Langue', push: 'Notifications push' },
      common: { system: 'Système', light: 'Clair', dark: 'Sombre', english: 'Anglais', swedish: 'Suédois' },
    },

    navigation: {
      tabs: {
        events: 'Événements',
        lists: 'Listes',
        claimed: 'Réservés',
        profile: 'Profil',
      },
    },

    eventList: {
      header: {
        welcome: 'Bon retour,',
        tagline: 'Coordonnez les cadeaux facilement',
        emptyName: 'toi',
      },
      stats: {
        activeEvents: 'Événements actifs',
        itemsClaimed: 'Articles réservés',
        toPurchase: 'To buy',
      },
      title: 'Vos événements',
      toolbar: { create: 'Créer', join: 'Rejoindre' },

      empty: {
        title: 'Aucun événement pour l’instant.',
        body: 'Créez votre premier événement ou rejoignez-en un avec un code.',
        create: 'Créer un événement',
        join: 'Rejoindre avec un code',
      },

      eventCard: {
        members_one: '{{count}} membre',
        members_other: '{{count}} membres',
        claimedShort: '{{claimed}}/{{total}} réservés',
        today: 'aujourd’hui',
        tomorrow: 'demain',
        inDays_one: 'dans {{count}} jour',
        inDays_other: 'dans {{count}} jours',
        daysAgo_one: 'il y a {{count}} jour',
        daysAgo_other: 'il y a {{count}} jours',
        noDate: 'Pas de date',
      },

      actions: { share: 'Partager', edit: 'Modifier', delete: 'Supprimer', leave: 'Quitter' },

      alerts: {
        deleteTitle: 'Supprimer l’event ?',
        deleteBody: 'Cela supprimera toutes les listes, articles et réservations pour tout le monde.',
        leaveTitle: 'Quitter l’event ?',
        leaveBody: 'Vous serez retiré de cet event et vos réservations seront effacées.',
        cancel: 'Annuler',
        confirmDelete: 'Supprimer',
        confirmLeave: 'Quitter',
      },

      errors: {
        loadFailed: 'Échec du chargement des événements',
        generic: 'Un problème est survenu',
      },
    },

    eventDetail: {
      header: {
        adminNote: 'Vous êtes admin de cet event.',
        memberNote: 'Accès membre',
      },
      stats: {
        members: 'Membres',
        items: 'Articles',
        claimed: 'Réservés',
      },
      toolbar: {
        edit: 'Modifier',
        delete: 'Supprimer',
      },
      actions: {
        share: 'Partager',
        leave: 'Quitter',
        createList: 'Créer une liste',
      },
      members: {
        title: 'Membres',
        show: 'Afficher',
        hide: 'Masquer',
        remove: 'Retirer',
        roles: {
          giver: 'donneur',
          recipient: 'bénéficiaire',
          admin: 'admin',
        },
      },
      lists: {
        title: 'Listes',
        emptyTitle: 'Pas encore de listes.',
        emptyBody: 'Créez-en une pour commencer.',
      },
      invite: {
        title: 'Options d’invitation',
        emailLabel: 'Envoyer un e-mail',
        emailPlaceholder: 'nom@exemple.com',
        cancel: 'Annuler',
        sendEmail: 'Envoyer l’e-mail',
        sending: 'Envoi…',
        sendCode: 'Envoyer le code',
        sentTitle: 'Invitation envoyée',
        sentBody: 'Votre invitation a été envoyée par e-mail.',
        missingEmailTitle: 'E-mail manquant',
        missingEmailBody: 'Veuillez saisir une adresse e-mail.',
        sendFailedTitle: 'Échec de l’envoi',
      },
      share: {
        joinWithCode: 'Rejoignez mon event « {{title}} » : code {{code}}',
      },
      alerts: {
        notAllowedTitle: 'Non autorisé',
        onlyAdminDelete: 'Seul un admin peut supprimer cet event.',
        deleteTitle: 'Supprimer l’event ?',
        deleteBody: 'Cela supprimera toutes les listes, articles et réservations pour tout le monde.',
        cancel: 'Annuler',
        confirmDelete: 'Supprimer',

        loadErrorTitle: 'Erreur de chargement',

        removeMemberTitle: 'Retirer ce membre ?',
        removeMemberBody: 'Il sera retiré de l’event et ses réservations seront effacées.',
        removeFailed: 'Échec du retrait',
        alreadyRemoved: 'Déjà retiré',
        memberRemoved: 'Membre retiré',

        leaveTitle: 'Quitter l’event ?',
        leaveBody: 'Vous serez retiré de cet event et vos réservations seront effacées.',
        notMember: 'Pas membre',
        leaveFailed: 'Échec du départ',
        leftEvent: 'Event quitté',
      },
    },

    editEvent: {
      title: 'Modifier l’event',
      labels: {
        title: 'Titre',
        date: 'Date',
        joinCode: 'Code d’invitation',
      },
      placeholders: {
        title: 'ex. Anniversaire de Bob',
        date: 'AAAA-MM-JJ',
        selectDate: 'Sélectionner une date',
      },
      actions: {
        retry: 'Réessayer',
        back: 'Retour',
        copy: 'Copier',
        save: 'Enregistrer les modifications',
      },
      states: {
        viewOnly: 'Lecture seule (pas admin)',
        saving: 'Enregistrement…',
      },
      messages: {
        signInRequired: 'Connexion requise.',
        notAllowed: 'Non autorisé',
        onlyAdmins: 'Seuls les admins peuvent modifier.',
        titleRequired: 'Titre requis',
        enterTitle: 'Veuillez saisir un titre.',
        eventUnavailable: 'Event indisponible.',
        copied: 'Code copié',
        copyFailed: 'Échec de la copie',
        updated: 'Event mis à jour',
        saveFailed: 'Échec de l’enregistrement',
        failedToLoad: 'Impossible de charger l’event.',
        notFound: 'Event introuvable ou accès refusé.',
      },
    },

    createList: {
      title: 'Créer une liste',
      labels: {
        listName: 'Nom de la liste',
      },
      placeholders: {
        listName: 'ex. Cadeaux pour Bob',
      },
      sections: {
        recipients: {
          title: 'Bénéficiaires (pour qui est cette liste)',
          help: 'Touchez pour sélectionner un ou plusieurs bénéficiaires.',
        },
        visibility: {
          title: 'Visibilité',
          help: 'Choisissez qui peut voir cette liste.',
        },
        exclusions: {
          title: 'Qui exclure',
          help: 'Les personnes choisies ici ne verront pas cette liste (même si elles sont bénéficiaires).',
        },
      },
      visibility: {
        public: 'Visible par tous',
        exclude: 'Exclure des personnes',
      },
      actions: {
        create: 'Créer la liste',
      },
      states: {
        creating: 'Création…',
      },
      toasts: {
        loadError: 'Erreur de chargement',
        notSignedIn: 'Non connecté',
        listNameRequired: 'Nom de la liste requis',
        recipientsRequired: {
          title: 'Bénéficiaires requis',
          body: 'Sélectionnez au moins un bénéficiaire.',
        },
        createFailed: {
          title: 'Échec de la création',
          noId: 'Aucun ID de liste retourné.',
        },
        notMember: 'Vous n’êtes pas membre de cet event.',
        created: {
          title: 'Liste créée',
          body: 'Votre liste a été créée.',
        },
      },
      user: 'Utilisateur {{id}}',
    },

    addItem: {
      title: 'Ajouter un article',
      labels: {
        name: 'Nom de l’article',
        urlOpt: 'URL (optionnel)',
        priceOpt: 'Prix (optionnel)',
        notesOpt: 'Notes (optionnel)',
      },
      placeholders: {
        name: 'ex. Casque à réduction de bruit',
        url: 'ex. https://exemple.com/produit',
        price: 'ex. 149,99',
        notes: 'ex. Préfère les modèles circum-auriculaires',
      },
      actions: {
        add: 'Ajouter',
      },
      states: {
        adding: 'Ajout…',
      },
      toasts: {
        itemNameRequired: { title: 'Nom requis', body: 'Veuillez saisir un nom.' },
        invalidPrice:     { title: 'Prix invalide', body: 'Entrez un nombre comme 19,99' },
        notSignedIn: 'Non connecté',
        added: 'Article ajouté',
        addFailed: { title: 'Échec de l’ajout' },
      },
      errors: {
        generic: 'Erreur',
      },
    },

    listDetail: {
      title: 'Liste',
      actions: {
        addItem: 'Ajouter un article',
        delete: 'Supprimer',
      },
      empty: 'Aucun article pour le moment.',
      summary: {
        label: 'Réservés : {{claimed}} · Non réservés : {{unclaimed}}',
      },
      item: {
        notClaimed: 'Pas encore réservé',
        claimedByYou: 'Réservé par : Vous',
        claimedByName: 'Réservé par : {{name}}',
        hiddenForRecipients: 'L’acheteur reste caché pour les bénéficiaires.',
        someone: 'Quelqu’un',
      },
      confirm: {
        deleteItemTitle: 'Supprimer l’article ?',
        deleteItemBody: 'Cela supprimera « {{name}} » et ses réservations.',
        deleteListTitle: 'Supprimer cette liste ?',
        deleteListBody: 'Cela supprimera la liste et tous ses articles et réservations. Action irréversible.',
      },
      errors: {
        generic: 'Erreur',
        load: 'Un problème est survenu lors du chargement de la liste.',
        notFound: 'Cette liste n’existe pas ou l’accès est refusé.',
        notAllowed: 'Non autorisé',
        cannotDeleteBody: 'Vous ne pouvez pas supprimer cet article.',
        hasClaimsTitle: 'Impossible de supprimer',
        hasClaimsBody: 'Annulez les réservations d’abord ou contactez un admin/propriétaire.',
        alreadyGoneTitle: 'Déjà supprimé',
        alreadyGoneBody: 'Cet article n’existe plus.',
        deleteFailed: 'Échec de la suppression',
        directDeleteBlocked: 'Suppression directe bloquée',
        goBack: 'Retour',
      },
    },

    allLists: {
      title: 'Toutes les listes',
      eventLabel: 'Événement : {{title}}',
      event: 'Événement',
      empty: 'Aucune liste visible pour le moment.',
    },

    myClaims: {
      title: 'Mes articles réservés',
      line: '{{event}} · {{list}}',
      markPurchased: 'Marquer comme acheté',
      markNotPurchased: 'Marquer non acheté',
      empty: 'Vous n’avez rien réservé pour l’instant.',
      updateFailed: 'Échec de la mise à jour',
      fallbackItem: 'Article',
      fallbackList: 'Liste',
      fallbackEvent: 'Événement',
    },

    createEvent: {
      titleLabel: 'Titre',
      titlePlaceholder: 'ex. Anniversaire de Bob',
      descriptionLabel: 'Description (optionnel)',
      descriptionPlaceholder: 'ex. Lieu, thème, notes…',
      dateLabel: 'Date de l’event (optionnel)',
      datePlaceholder: 'Sélectionner une date',
      done: 'Terminé',
      recursLabel: 'Récurrence',
      recurs: { none: 'Aucune', weekly: 'Hebdomadaire', monthly: 'Mensuelle', yearly: 'Annuelle' },
      create: 'Créer',
      creating: 'Création…',
      toastMissingTitleTitle: 'Titre manquant',
      toastMissingTitleBody: 'Veuillez saisir un titre d’event.',
      toastCreated: 'Event créé',
      toastCreateFailed: 'Échec de la création',
    },

    joinEvent: {
      heading: 'Rejoindre un event',
      codeLabel: 'Saisir le code',
      codePlaceholder: 'ex. 7G4K-MQ',
      join: 'Rejoindre',
      joining: 'Rejoint…',
      alertEnterTitle: 'Saisir un code',
      alertEnterBody: 'Collez le code d’invitation.',
      alertInvalidTitle: 'Code invalide',
      alertInvalidBody: 'Ce code est introuvable.',
      alertFailedTitle: 'Échec de la jonction',
    },
  },
} as const;

export default fr;
