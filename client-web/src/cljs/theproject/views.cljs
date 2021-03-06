(ns theproject.views
  (:require [re-frame.core :as re-frame]
            [ajax.core :as ajax]
            [clojure.string :as string]
            [reagent.core :as reagent]
            [cljs.core.match :refer-macros [match]]
            [secretary.core :as secretary]
            [pushy.core :as pushy]
            [cljs-time.core :as cljs-time]
            [cljs-time.format]
            ))

(let [name (re-frame/subscribe [:name])
      cards (re-frame/subscribe [:cards])
      ]
  (defn home-panel []
    [:div (str "Hello from " @name ". This is the Home Page.")
     [:div [:a {:href "/about"} "create card"]]
     [:input {:type "button"
              :value "reload cards"
              :on-click #(re-frame/dispatch [:request-it])
              }]
     (into [:div]
           (for [d (distinct (flatten (for [c @cards] (:decks_list c))))]
             [:p [:a {:href (str "/deck/" d)} d]]
             ))
     [:table.superlearn (into [:tbody]
                   ;; (for [c (filter (fn [coll] (some #(= % "whatever") (:decks_list coll))) @cards)]
                                ;; (for [c (sort-by :due @cards)]
                              (apply concat
                                     (for [[i group] (map-indexed vector (partition-by :due (sort-by :due @cards)))]
                                       (for [c group]
                                         ^{:key c}
                                         [:tr (when (odd? i) {:class "grey"})
                                          [:td (str (:due c)) " " [:a {:href (str "/card/" (:card_id c))} "c"]]
                                          ;; [:td {:dangerouslySetInnerHTML {:__html (-> (:front c) str js/marked)}}]
                                          [:td {:ref (fn [el]
                                                       (when el
                                                         (if-not (re-find #"\\\(|\\\[" (.-innerHTML el))   ; was also |\$.*\$
                                                           (set! (.-innerHTML el) (-> (:front c) str js/marked))
                                                           (do (set! (.-innerHTML el) (js/MyEscape (.-innerHTML el)))
                                                               (js/MathJax.Hub.Queue #js ["Typeset" js/MathJax.Hub el]
                                                                                     #js ["MyDone" js/window el]))
                                                           )
                                                         ))}
                                           (:front c)
                                           ]
                                          [:td (str (:decks_list c))]
                                          ])))
                              ;;   )
                              ;; (apply concat
                              ;;        (for [[i lst] (map-indexed vector (partition-by :due (sort-by :due @cards)))]
                              ;;          (for [c lst]
                              ;;            ^{:key c}
                              ;;            [:tr (if (odd? i) {:style {:background-color "red"}})
                              ;;             [:td (:due c)]
                              ;;             ]
                              ;;            )

                              ;;          ))
                              
                              
                              )]
     ]))

;; about

(defn about-panel []
  [:div "This is the About Page."
   [:div [:a {:href "/"} "go to Home Page"]]

   [:textarea {
               ;; :on-key-down #(when (and       ; http://stackoverflow.com/questions/1684196/ctrlenter-jquery-in-textarea/36478923#36478923
               ;;                      (or (.-ctrlKey %) (.-metaKey %))
               ;;                      (or (= 13 (.-keyCode %)) (= 10 (.-keyCode %))))
               ;;                 (re-frame/dispatch [:post-it (-> % .-target .-value)])
               ;;                 (set! (-> % .-target .-value) ""))
               :id "front"
               :auto-focus true
               :rows 5
               :cols 40
               }]
   [:textarea {:id "back"
               :rows 5
               :cols 40
               }]
   [:input {:type "text"
            :id "deck_name"}]
   [:input {:type "text"
            :id "context_url"}]
   [:input {:type "button"     ; TODO: get values of front and back not by using getElementById(), but by using inputElement.form or document.querySelectorAll()
            :value "add card"
            :on-click #(let [front         (.getElementById js/document "front")
                             back          (.getElementById js/document "back")
                             deck_name     (.getElementById js/document "deck_name")
                             context_url   (.getElementById js/document "context_url")
                             ]
                         (js/console.log (.-value front)
                                         (.-value back))
                         (re-frame/dispatch [:post-it (.-value front) (.-value back) (.-value deck_name) (.-value context_url)])
                         (set! (-> front .-value) "")
                         (set! (-> back  .-value) "")
                        )}]
   ])

(let [cards (re-frame/subscribe [:cards])
      ]
  (defn card-panel [card_id]
    [:div
     [:a {:href "/"} "home"]
      (let [c (first (filter (comp #{card_id} :card_id) @cards))]
        (when c
          [:div
           [:div
            ;; [:div.card {:dangerouslySetInnerHTML {:__html (-> (:front c) str js/marked)}}]
            ;; [:div.card {:dangerouslySetInnerHTML {:__html (-> (:back  c) str js/marked)}}]
            [:div {:ref (fn [el]
                          (when (and el
                                     (re-find #"\$|\(" (.-innerHTML el))
                                     )
                           (js/MathJax.Hub.Queue #js ["Typeset" js/MathJax.Hub el])
                           ))}
             (:front c)
             ]
            [:div {:ref (fn [el]
                          (when (and el
                                     (re-find #"\$|\(" (.-innerHTML el))
                                     )
                           (js/MathJax.Hub.Queue #js ["Typeset" js/MathJax.Hub el])
                           ))}
             (:back c)
             ]

            [:p ":decks_list " (str (:decks_list c))]
            [:p ":contexts_list " (str (:contexts_list c))]
            [:p ":added_at " (:added_at  c)]
            [:p ":due: " (:due c)]
            [:p ":prev_response " (:prev_response c)]
            [:p ":prev_interval " (:prev_interval c)]
            [:p ":easiness_factor " (:easiness_factor c)]
            [:p ":num_of_lapses " (:num_of_lapses c)]
            [:p ":prev_seconds_spent_on_card " (:prev_seconds_spent_on_card c)]
            ;; [:p (str c)]
            [:input {:type "button" :value "again"  :on-click #(re-frame/dispatch [:review-card card_id 0])}]
            [:input {:type "button" :value "easy" :on-click #(re-frame/dispatch [:review-card card_id 3])}]
            [:input {:type "button" :value "normal" :on-click #(re-frame/dispatch [:review-card card_id 4])}]
            [:p]
            ]
           [:div
            [:textarea {
                        :id "front"
                        :auto-focus true
                        :rows 5
                        :cols 40
                        :defaultValue (:front c)
                        }]
            [:textarea {:id "back"
                        :rows 5
                        :cols 40
                        :defaultValue (:back c)
                        }]
            [:input {:type "button"
                     :value "edit card content"
                     :on-click #(let [front         (.-value (.getElementById js/document "front"))
                                      back          (.-value (.getElementById js/document "back"))
                                      ]
                                  (when-not (and (= front (:front c))
                                                 (= back  (:back c)))
                                    (re-frame/dispatch [:edit-card-content card_id front back])
                                    )
                                  )}]]
           ])
        )
     ])
  )

(let [cards (re-frame/subscribe [:cards])
      ]
  (defn deck-panel [deck_id]
    [:div
     [:a {:href "/"} "home"]
     [:p (str deck_id)]
     ]))

;; main

(defn panels [panel-name]
  (match panel-name
    :home-panel [home-panel]
    :about-panel [about-panel]
    [:card-panel card_id] [card-panel card_id]
    [:deck-panel deck_id] [deck-panel deck_id]
    [:div]))

;; (defn show-panel [panel-name]
;;   [panels panel-name])


(defn main-panel []
  (let [active-panel (re-frame/subscribe [:active-panel])]
    (fn []
      ;; [show-panel @active-panel]
      [panels @active-panel]
      )))
